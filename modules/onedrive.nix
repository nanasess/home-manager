{ pkgs, ... }:

{
  home.packages = [ pkgs.onedrive ];

  xdg.configFile."onedrive/config".text = ''
    sync_dir = "~/OneDrive - Skirnir Inc"
  '';

  xdg.configFile."onedrive/sync_list".text = ''
    emacs
  '';

  systemd.user.services.onedrive = {
    Unit = {
      Description = "OneDrive Free Client";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      ExecStart = "${pkgs.onedrive}/bin/onedrive --monitor";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
