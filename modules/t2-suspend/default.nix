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

  # 配置先 (系統的に t2linux / systemd 標準の場所)。
  hookDest = "/usr/lib/systemd/system-sleep/${sleepHookName}";
  confDest = "/etc/systemd/sleep.conf.d/${sleepConfName}";
  lidDest = "/etc/systemd/logind.conf.d/${lidConfName}";
in
{
  # 素材ファイル (リポジトリが真実) をユーザー空間に置く。ヘルパーはここから配る。
  home.file."${shareDir}/${sleepHookName}" = {
    source = ./t2-apple-bce;
    executable = true;
  };
  home.file."${shareDir}/${sleepConfName}".source = ./10-t2-no-hibernate.conf;
  home.file."${shareDir}/${lidConfName}".source = ./10-t2-lid-suspend.conf;

  # 特権配置ヘルパー (check-system-packages と同型)。sudo は明示的な単一操作に隔離。
  home.file.".local/bin/t2-suspend-install" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      SRC_HOOK="${shareDir}/${sleepHookName}"
      SRC_CONF="${shareDir}/${sleepConfName}"
      SRC_LID="${shareDir}/${lidConfName}"
      DST_HOOK="${hookDest}"
      DST_CONF="${confDest}"
      DST_LID="${lidDest}"

      if [ "''${1:-}" = "--uninstall" ]; then
        echo "== T2 サスペンド回避策をアンインストール =="
        sudo rm -fv "$DST_HOOK" "$DST_CONF" "$DST_LID"
        sudo systemctl daemon-reload || true
        echo "完了。デフォルト (回避策・蓋閉じ設定なし) に戻りました。"
        echo "蓋閉じ設定の反映には logind の再起動または再起動が必要:"
        echo "  sudo systemctl restart systemd-logind   (Wayland では概ね安全)"
        exit 0
      fi

      echo "== T2 サスペンド回避策 + 蓋閉じサスペンドをインストール =="
      echo "  hook : $SRC_HOOK -> $DST_HOOK"
      echo "  sleep: $SRC_CONF -> $DST_CONF"
      echo "  lid  : $SRC_LID  -> $DST_LID"
      echo
      echo "注意: 初回の suspend テストは外部 USB キーボードを接続して行うこと。"
      echo "      復帰時に apple_bce のリロードが失敗すると内蔵入力が使えなくなる。"
      echo

      sudo install -D -m 0755 "$SRC_HOOK" "$DST_HOOK"
      sudo install -D -m 0644 "$SRC_CONF" "$DST_CONF"
      sudo install -D -m 0644 "$SRC_LID" "$DST_LID"
      sudo systemctl daemon-reload

      echo
      echo "配置完了。"
      echo "蓋閉じサスペンドの反映には logind の再起動または OS 再起動が必要:"
      echo "  sudo systemctl restart systemd-logind   (Wayland/GNOME では概ね安全。"
      echo "                                            不安なら OS 再起動でも可)"
      echo
      echo "確認:"
      echo "  cat /sys/power/mem_sleep        # [deep] が選択されているか"
      echo "  systemd-analyze cat-config systemd/logind.conf | grep HandleLidSwitch"
      echo "テスト:  systemctl suspend   (外部キーボード接続の上で) / 蓋を閉じる"
    '';
  };
}
