{ lib, rustPlatform, fetchFromGitHub, pkg-config, openssl }:

# yaskkserv2 (skkserv) を Nix でパッケージ化する。nixpkgs / apt には無いため、
# 上流 (wachikun/yaskkserv2) を rustPlatform.buildRustPackage で直接ビルドする。
# これにより wsl-gentoo (portage) と ubuntu で同一バイナリを共有でき、どちらの
# ホストも sudo emerge / apt を経ずに yaskkserv2 と yaskkserv2_make_dictionary を
# 得られる (modules/yaskkserv2.nix で参照)。
rustPlatform.buildRustPackage rec {
  pname = "yaskkserv2";
  version = "0.1.7";

  src = fetchFromGitHub {
    owner = "wachikun";
    repo = "yaskkserv2";
    rev = version;
    hash = "sha256-bF8OHP6nvGhxXNvvnVCuOVFarK/n7WhGRktRN4X5ZjE=";
  };

  cargoHash = "sha256-cycs8Zism228rjMaBpNYa4K1Ll760UhLKkoTX6VJRU0=";

  # reqwest が default-tls (OpenSSL) を要求するため pkg-config + openssl が必要。
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

  # 一部のテストはネットワーク / 実辞書を要求するためビルド時は無効化する。
  doCheck = false;

  meta = with lib; {
    description = "Yet Another Skkserv 2 — SKK 辞書サーバ";
    homepage = "https://github.com/wachikun/yaskkserv2";
    license = with licenses; [ mit asl20 ];
    platforms = platforms.unix;
    mainProgram = "yaskkserv2";
  };
}
