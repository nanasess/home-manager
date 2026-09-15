#!/usr/bin/env bash
# OpenAI の apt リポジトリ (deb の postinst が登録するもの) の Packages インデックスから
# 最新の Version / Filename / SHA256 を読んで source.nix を書き換える。deb 本体は落とさない。
#
#   ./pkgs/chatgpt/update.sh && nix build .#chatgpt
set -euo pipefail

repo='https://persistent.oaistatic.com/codex-app-prod/linux/deb'
packages=$(curl -fsSL "$repo/dists/stable/main/binary-amd64/Packages")

version=$(printf '%s\n' "$packages" | sed -n 's/^Version: //p' | head -1)
filename=$(printf '%s\n' "$packages" | sed -n 's/^Filename: //p' | head -1)
sha256=$(printf '%s\n' "$packages" | sed -n 's/^SHA256: //p' | head -1)
hash=$(nix hash convert --hash-algo sha256 --to sri "$sha256")

cat > "$(dirname "${BASH_SOURCE[0]}")/source.nix" <<_EOF_
# update.sh が書き換える。手で編集するときは apt リポジトリの Packages インデックス
# ($repo/dists/stable/main/binary-amd64/Packages)
# の Version / Filename / SHA256 を写す。
{
  version = "$version";
  url = "$repo/$filename";
  hash = "$hash";
}
_EOF_
echo "chatgpt: $version"
