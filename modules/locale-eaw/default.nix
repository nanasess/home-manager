{ config, pkgs, lib, ... }:

let
  eawCharmap = ./UTF-8-EAW-CONSOLE.gz;
  localeDir = "${config.home.homeDirectory}/.local/share/locale";
in
{
  # locale-eaw EAW-CONSOLE: East Asian Ambiguous 文字の幅を適切に設定
  # https://github.com/hamano/locale-eaw
  # システムの glibc に含まれる localedef を使用する必要がある
  # Nix の localedef ではシステム glibc と互換性のないロケールデータが生成される可能性がある
  home.activation.localeEaw = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${localeDir}"
    charmap=$(${pkgs.coreutils}/bin/mktemp)
    ${pkgs.gzip}/bin/gunzip -c ${eawCharmap} > "$charmap"
    if [ -x /usr/bin/localedef ]; then
      /usr/bin/localedef -f "$charmap" -i ja_JP "${localeDir}/ja_JP.utf8" || \
        echo "warning: localedef failed, East Asian Ambiguous width may not work correctly" >&2
    else
      echo "warning: /usr/bin/localedef not found, skipping locale-eaw setup" >&2
    fi
    ${pkgs.coreutils}/bin/rm -f "$charmap"
  '';

  home.sessionVariables = {
    LOCPATH = "${localeDir}:/usr/lib/locale";
  };
}
