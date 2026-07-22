{ config, ... }:
# T2 Mac サスペンド回避策を home-manager 管理下に置くモジュール (Ubuntu 用)。
#
# 選択肢3 (apple_bce の unload/reload) の本体は root 権限 + システムの
# サスペンド遷移フックを要するため、スタンドアロン home-manager の
# systemd.user.services では実現できない (issue #111 参照)。
# そこでリポジトリを source-of-truth とし、
#   - 素材ファイルを ~/.local/share/t2-suspend/ に canonical コピーとして配置
#   - ~/.local/bin/t2-suspend-install で以下へ sudo 配置する
#       * /usr/lib/systemd/system-sleep/   (apple_bce unload/reload フック)
#       * /etc/systemd/sleep.conf.d/        (hibernation 無効化)
#       * /etc/systemd/logind.conf.d/       (蓋閉じサスペンド有効化)
#       * /etc/udev/rules.d/                (BCE VHCI の USB autosuspend 無効化・実験的)
# という形で「宣言・再現性」と「明示的で監査可能な特権操作」を両立する。
#
# 使い方:
#   home-manager switch  でファイルとヘルパーが配置される (システム無変更)。
#   実際に有効化するとき (保留可) に一度だけ:  sudo ~/.local/bin/t2-suspend-install
#   無効化:  sudo ~/.local/bin/t2-suspend-install --uninstall
let
  shareDir = "${config.xdg.dataHome}/t2-suspend";
  sleepHookName = "t2-apple-bce";
  sleepConfName = "10-t2-no-hibernate.conf";
  lidConfName = "10-t2-lid-suspend.conf";
  udevRuleName = "90-t2-usb-no-autosuspend.rules";

  # 配置先 (系統的に t2linux / systemd 標準の場所)。
  hookDest = "/usr/lib/systemd/system-sleep/${sleepHookName}";
  confDest = "/etc/systemd/sleep.conf.d/${sleepConfName}";
  lidDest = "/etc/systemd/logind.conf.d/${lidConfName}";
  udevDest = "/etc/udev/rules.d/${udevRuleName}";
in
{
  # 素材ファイル (リポジトリが真実) をユーザー空間に置く。ヘルパーはここから配る。
  home.file."${shareDir}/${sleepHookName}" = {
    source = ./t2-apple-bce;
    executable = true;
  };
  home.file."${shareDir}/${sleepConfName}".source = ./10-t2-no-hibernate.conf;
  home.file."${shareDir}/${lidConfName}".source = ./10-t2-lid-suspend.conf;
  home.file."${shareDir}/${udevRuleName}".source = ./90-t2-usb-no-autosuspend.rules;

  # 特権配置ヘルパー (check-system-packages と同型)。sudo は明示的な単一操作に隔離。
  home.file.".local/bin/t2-suspend-install" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      SRC_HOOK="${shareDir}/${sleepHookName}"
      SRC_CONF="${shareDir}/${sleepConfName}"
      SRC_LID="${shareDir}/${lidConfName}"
      SRC_UDEV="${shareDir}/${udevRuleName}"
      DST_HOOK="${hookDest}"
      DST_CONF="${confDest}"
      DST_LID="${lidDest}"
      DST_UDEV="${udevDest}"

      if [ "''${1:-}" = "--uninstall" ]; then
        echo "== T2 サスペンド回避策をアンインストール =="
        sudo rm -fv "$DST_HOOK" "$DST_CONF" "$DST_LID" "$DST_UDEV"
        sudo systemctl daemon-reload || true
        sudo udevadm control --reload-rules || true
        echo "完了。デフォルト (回避策・蓋閉じ設定なし) に戻りました。"
        echo "蓋閉じ設定の変更を反映するには OS を再起動すること。"
        echo "  警告: 稼働中の GNOME/Wayland セッション下で"
        echo "        'systemctl restart systemd-logind' を実行してはいけない。"
        echo "        セッションの入力デバイスが切り離され、キーボード/トラックパッドが"
        echo "        操作不能になり強制電源OFFが必要になる (issue #111 参照)。"
        exit 0
      fi

      echo "== T2 サスペンド回避策 + 蓋閉じサスペンドをインストール =="
      echo "  hook : $SRC_HOOK -> $DST_HOOK"
      echo "  sleep: $SRC_CONF -> $DST_CONF"
      echo "  lid  : $SRC_LID  -> $DST_LID"
      echo "  udev : $SRC_UDEV -> $DST_UDEV"
      echo
      echo "注意: 初回の suspend テストは外部 USB キーボードを接続して行うこと。"
      echo "      復帰時に apple_bce のリロードが失敗すると内蔵入力が使えなくなる。"
      echo

      sudo install -D -m 0755 "$SRC_HOOK" "$DST_HOOK"
      sudo install -D -m 0644 "$SRC_CONF" "$DST_CONF"
      sudo install -D -m 0644 "$SRC_LID" "$DST_LID"
      sudo install -D -m 0644 "$SRC_UDEV" "$DST_UDEV"
      sudo systemctl daemon-reload
      sudo udevadm control --reload-rules

      # udev ルールを現行の BCE VHCI デバイスへ即適用 (再起動不要・安全な sysfs 書込)。
      # ルート ADD トリガの再発火は USB 再プローブを招きうるため、power/control を
      # 直接 on にする方式を採る。
      for ctrl in /sys/bus/usb/devices/*/power/control; do
        dev=$(dirname "$(dirname "$ctrl")")
        if readlink -f "$dev" | grep -q 'apple-bce/apple-bce/bce-vhci'; then
          echo on | sudo tee "$ctrl" >/dev/null || true
        fi
      done

      echo
      echo "配置完了。"
      echo "蓋閉じサスペンド (logind 設定) の反映には OS の再起動が必要。"
      echo "  警告: 稼働中の GNOME/Wayland セッション下で"
      echo "        'systemctl restart systemd-logind' を実行してはいけない。"
      echo "        セッションの入力デバイスが切り離され、キーボード/トラックパッドが"
      echo "        操作不能になり強制電源OFFが必要になる (実際に発生。issue #111 参照)。"
      echo "        apple_bce フックと hibernation 設定は再起動不要で即有効。"
      echo
      echo "確認:"
      echo "  cat /sys/power/mem_sleep        # [deep] が選択されているか"
      echo "  systemd-analyze cat-config systemd/logind.conf | grep HandleLidSwitch"
      echo "  cat /sys/bus/usb/devices/usb5/power/control   # bce-vhci ルートハブが on か"
      echo "テスト:  systemctl suspend   (外部キーボード接続の上で) / 蓋を閉じる"
      echo "  ※ USB autosuspend 無効化は長時間サスペンド復帰の緩和 (実験的)。"
      echo "    効果は 8h+ サスペンド後の初回復帰で入力が戻るかで判定する。"
    '';
  };
}
