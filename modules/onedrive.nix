{ ... }:

{
  xdg.configFile."onedrive/config".text = ''
    sync_dir = "~/OneDrive - Skirnir Inc"
  '';

  xdg.configFile."onedrive/sync_list".text = ''
    emacs
  '';
}
