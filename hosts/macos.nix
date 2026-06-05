{ config, pkgs, lib, ... }:

let
  # Homebrew で管理するパッケージ一覧
  # brew list --formula / brew list --cask で確認
  brewPackages = [
    # TODO: 実環境から精査して追加
  ];
  brewCasks = [
    # TODO: 実環境から精査して追加
  ];
in
{
  home.homeDirectory = "/Users/nanasess";

  # 字形本体の Noto。home.nix 共通から移動 (Ubuntu のみ OS 静的 Noto に委譲する方針)。
  # macOS の Emacs は CoreText (ns) バックエンドのため可変フォントでも問題ない。
  home.packages = with pkgs; [
    noto-fonts
  ];

  programs.git.signing.signer = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";

  home.file.".local/bin/check-system-packages" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      echo "=== Homebrew パッケージ差分チェック ==="
      missing=0
      for pkg in ${lib.concatStringsSep " " brewPackages}; do
        if ! brew list --formula 2>/dev/null | grep -q "^''${pkg}$"; then
          echo "MISSING (formula): $pkg"
          missing=$((missing + 1))
        fi
      done
      for pkg in ${lib.concatStringsSep " " brewCasks}; do
        if ! brew list --cask 2>/dev/null | grep -q "^''${pkg}$"; then
          echo "MISSING (cask): $pkg"
          missing=$((missing + 1))
        fi
      done
      if [ "$missing" -eq 0 ]; then
        echo "OK: すべてのパッケージがインストールされています"
      else
        echo "---"
        echo "$missing 個のパッケージが未インストールです"
        exit 1
      fi
    '';
  };
}
