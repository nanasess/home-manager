{ config, pkgs, lib, ... }:

let
  eawCharmap = ./UTF-8-EAW-CONSOLE.gz;
  localeDir = "${config.home.homeDirectory}/.local/share/locale";
in
{
  # locale-eaw EAW-CONSOLE: East Asian Ambiguous 文字の幅を適切に設定
  # https://github.com/hamano/locale-eaw
  home.activation.localeEaw = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${localeDir}"
    charmap=$(${pkgs.coreutils}/bin/mktemp)
    ${pkgs.gzip}/bin/gunzip -c ${eawCharmap} > "$charmap"
    /usr/bin/localedef -f "$charmap" -i ja_JP "${localeDir}/ja_JP.utf8" 2>/dev/null || true
    ${pkgs.coreutils}/bin/rm -f "$charmap"
  '';

  home.sessionVariables = {
    LOCPATH = "${localeDir}:/usr/lib/locale";
  };
}
