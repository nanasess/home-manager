# wsl-nixos のユーザー環境。WSL 共通部分は modules/wsl。
{ ... }:

{
  home.homeDirectory = "/home/nanasess";

  # programs._1password (modules/nixos/common.nix) の security wrapper が
  # setgid onepassword-cli 付きで生成する。
  wsl.opLinux = "/run/wrappers/bin/op";
}
