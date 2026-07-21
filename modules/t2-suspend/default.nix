{ config, ... }:
# T2 Mac サスペンド回避策を home-manager 管理下に置くモジュール (Ubuntu 用)。
#
# 選択肢3 (apple_bce の unload/reload) の本体は root 権限 + システムの
# サスペンド遷移フックを要するため、スタンドアロン home-manager の
# systemd.user.services では実現できない (issue #111 参照)。
# そこでリポジトリを source-of-truth とし、
#   - 素材ファイルを ~/.local/share/t2-suspend/ に canonical コピーとして配置
#   - ~/.local/bin/t2-suspend-install で /usr/lib/systemd/system-sleep/ と
#     /etc/systemd/sleep.conf.d/ へ sudo 配置する
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

  # 配置先 (系統的に t2linux 標準の場所)。
  hookDest = "/usr/lib/systemd/system-sleep/${sleepHookName}";
  confDest = "/etc/systemd/sleep.conf.d/${sleepConfName}";
in
{
  # 素材ファイル (リポジトリが真実) をユーザー空間に置く。ヘルパーはここから配る。
  home.file."${shareDir}/${sleepHookName}" = {
    source = ./t2-apple-bce;
    executable = true;
  };
  home.file."${shareDir}/${sleepConfName}".source = ./10-t2-no-hibernate.conf;

  # 特権配置ヘルパー (check-system-packages と同型)。sudo は明示的な単一操作に隔離。
  home.file.".local/bin/t2-suspend-install" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      SRC_HOOK="${shareDir}/${sleepHookName}"
      SRC_CONF="${shareDir}/${sleepConfName}"
      DST_HOOK="${hookDest}"
      DST_CONF="${confDest}"

      if [ "''${1:-}" = "--uninstall" ]; then
        echo "== T2 サスペンド回避策をアンインストール =="
        sudo rm -fv "$DST_HOOK" "$DST_CONF"
        sudo systemctl daemon-reload || true
        echo "完了。デフォルト (回避策なし) に戻りました。"
        exit 0
      fi

      echo "== T2 サスペンド回避策をインストール =="
      echo "  hook: $SRC_HOOK -> $DST_HOOK"
      echo "  conf: $SRC_CONF -> $DST_CONF"
      echo
      echo "注意: 初回の suspend テストは外部 USB キーボードを接続して行うこと。"
      echo "      復帰時に apple_bce のリロードが失敗すると内蔵入力が使えなくなる。"
      echo

      sudo install -D -m 0755 "$SRC_HOOK" "$DST_HOOK"
      sudo install -D -m 0644 "$SRC_CONF" "$DST_CONF"
      sudo systemctl daemon-reload

      echo
      echo "配置完了。確認:"
      echo "  cat /sys/power/mem_sleep        # [deep] が選択されているか"
      echo "  systemctl status systemd-suspend.service"
      echo "テスト:  systemctl suspend   (外部キーボード接続の上で)"
    '';
  };
}
