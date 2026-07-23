{ config, ... }:
# T2 Mac サスペンド設定を home-manager 管理下に置くモジュール (Ubuntu 用)。
#
# 実機検証で判明した事実 (issue #111):
#  - この 7.1.2-1-t2-noble カーネルの apple_bce は no-state suspend/resume の PM を
#    内蔵しており、短時間サスペンドはドライバ側で復帰する
#    (apple-bce: resume: re-adding VHCI HCD after no-state wake)。
#  - apple_bce は音声/PCI が保持し refcnt=1 のため modprobe -r で unload できない。
#    旧 system-sleep フック (apple_bce の unload/reload) は事実上 no-op だった → 削除。
#  - 8時間超の長時間 deep-S3 は T2 コントローラの電源復帰失敗
#    (pci_pm_resume -5 / -110) で初回復帰時に内蔵キーボード/トラックパッドが
#    戻らない。これはハード/ファーム層の限界で、system-sleep フックや
#    USB autosuspend 無効化では直せない (どちらも実機で無効を確認)。
#    本命は将来カーネルのドライバ改善 (stateful sleep)。短時間サスペンドは動く。
#
# 従って本モジュールは「実際に効く2点」に絞る:
#   * /etc/systemd/sleep.conf.d/   hibernation 無効化 (suspend-then-hibernate 失敗回避)
#   * /etc/systemd/logind.conf.d/  蓋閉じ → サスペンド有効化
# いずれも root/システムレベルで home-manager 管轄外のため、リポジトリを
# source-of-truth とし ~/.local/bin/t2-suspend-install で sudo 配置する。
#
# 使い方:
#   home-manager switch  でファイルとヘルパーが配置される (システム無変更)。
#   sudo ~/.local/bin/t2-suspend-install              # 配置 (蓋閉じ反映は OS 再起動)
#   sudo ~/.local/bin/t2-suspend-install --uninstall  # 撤去
let
  shareDir = "${config.xdg.dataHome}/t2-suspend";
  sleepConfName = "10-t2-no-hibernate.conf";
  lidConfName = "10-t2-lid-suspend.conf";

  confDest = "/etc/systemd/sleep.conf.d/${sleepConfName}";
  lidDest = "/etc/systemd/logind.conf.d/${lidConfName}";

  # 旧版で配置していた無効な成果物。整理のため install/uninstall 時に撤去する。
  staleHook = "/usr/lib/systemd/system-sleep/t2-apple-bce";
  staleUdev = "/etc/udev/rules.d/90-t2-usb-no-autosuspend.rules";
in
{
  # 素材ファイル (リポジトリが真実) をユーザー空間に置く。ヘルパーはここから配る。
  home.file."${shareDir}/${sleepConfName}".source = ./10-t2-no-hibernate.conf;
  home.file."${shareDir}/${lidConfName}".source = ./10-t2-lid-suspend.conf;

  # 特権配置ヘルパー (check-system-packages と同型)。sudo は明示的な単一操作に隔離。
  home.file.".local/bin/t2-suspend-install" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      SRC_CONF="${shareDir}/${sleepConfName}"
      SRC_LID="${shareDir}/${lidConfName}"
      DST_CONF="${confDest}"
      DST_LID="${lidDest}"
      STALE_HOOK="${staleHook}"
      STALE_UDEV="${staleUdev}"

      # 旧版の無効な成果物 (modprobe フック / 効果のなかった udev ルール) を撤去。
      remove_stale() {
        if [ -e "$STALE_HOOK" ] || [ -e "$STALE_UDEV" ]; then
          echo "== 旧版の無効な配置物を撤去 =="
          sudo rm -fv "$STALE_HOOK" "$STALE_UDEV"
          sudo udevadm control --reload-rules || true
        fi
      }

      if [ "''${1:-}" = "--uninstall" ]; then
        echo "== T2 サスペンド設定をアンインストール =="
        sudo rm -fv "$DST_CONF" "$DST_LID"
        remove_stale
        sudo systemctl daemon-reload || true
        echo "完了。デフォルトに戻りました。"
        echo "蓋閉じ設定の変更を反映するには OS を再起動すること。"
        echo "  警告: 稼働中の GNOME/Wayland セッション下で"
        echo "        'systemctl restart systemd-logind' を実行してはいけない"
        echo "        (入力デバイスが切り離され強制電源OFFに至る。issue #111 参照)。"
        exit 0
      fi

      echo "== T2 サスペンド設定をインストール (hibernation 無効化 + 蓋閉じ有効化) =="
      echo "  sleep: $SRC_CONF -> $DST_CONF"
      echo "  lid  : $SRC_LID  -> $DST_LID"
      echo

      remove_stale
      sudo install -D -m 0644 "$SRC_CONF" "$DST_CONF"
      sudo install -D -m 0644 "$SRC_LID" "$DST_LID"
      sudo systemctl daemon-reload

      echo
      echo "配置完了。"
      echo "蓋閉じサスペンド (logind 設定) の反映には OS の再起動が必要。"
      echo "  警告: 稼働中の GNOME/Wayland セッション下で"
      echo "        'systemctl restart systemd-logind' を実行してはいけない"
      echo "        (入力デバイスが切り離され強制電源OFFに至る。実際に発生。issue #111 参照)。"
      echo
      echo "確認:"
      echo "  cat /sys/power/mem_sleep   # [deep] が選択されているか"
      echo "  systemd-analyze cat-config systemd/logind.conf | grep HandleLidSwitch"
      echo
      echo "注意: 短時間サスペンドはドライバ内蔵 PM で復帰する。8時間超の長時間"
      echo "      サスペンドは T2 の電源復帰限界で初回復帰時に入力が戻らないことが"
      echo "      ある (既知の限界。本モジュールでは解決しない。issue #111 参照)。"
    '';
  };
}
