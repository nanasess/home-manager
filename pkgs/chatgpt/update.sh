#!/usr/bin/env bash
# OpenAI の apt リポジトリ (deb の postinst が登録するもの) の Packages インデックスから
# 最新の Version / Filename / SHA256 を読んで source.nix を書き換える。deb 本体は落とさない。
#
#   ./pkgs/chatgpt/update.sh && nix build .#chatgpt
set -euo pipefail

repo='https://persistent.oaistatic.com/codex-app-prod/linux/deb'
packages=$(curl -fsSL "$repo/dists/stable/main/binary-amd64/Packages")

# Packages は空行区切りのスタンザ列で、他パッケージや旧バージョンのスタンザも並び得る。
# `Package: chatgpt` のスタンザだけを取り、その中で Version が最大の 1 スタンザから
# 3 値を読む (別スタンザの Filename / SHA256 を混ぜない)。
select_stanzas() {
  awk -v RS= -v ORS='\n\n' "$1"
}
chatgpt_stanzas=$(printf '%s\n' "$packages" | select_stanzas '/(^|\n)Package: chatgpt(\n|$)/')
if [ -z "$chatgpt_stanzas" ]; then
  echo "update.sh: Package: chatgpt のスタンザが Packages インデックスに見つからない" >&2
  exit 1
fi
version=$(printf '%s\n' "$chatgpt_stanzas" | sed -n 's/^Version: //p' | sort -V | tail -1)
stanza=$(printf '%s\n' "$chatgpt_stanzas" | select_stanzas "/(^|\n)Version: ${version//./\\.}(\n|$)/")
if [ "$(printf '%s\n' "$stanza" | grep -c '^Package: ')" -ne 1 ]; then
  echo "update.sh: Version $version のスタンザが 1 件に定まらない:" >&2
  printf '%s\n' "$stanza" >&2
  exit 1
fi

filename=$(printf '%s\n' "$stanza" | sed -n 's/^Filename: //p')
sha256=$(printf '%s\n' "$stanza" | sed -n 's/^SHA256: //p')
if [ -z "$filename" ] || [ -z "$sha256" ]; then
  echo "update.sh: 選んだスタンザに Filename / SHA256 が無い:" >&2
  printf '%s\n' "$stanza" >&2
  exit 1
fi
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
