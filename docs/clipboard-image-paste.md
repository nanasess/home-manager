# クリップボード画像ペースト (Claude Code)

Issue #133 の調査結果。ホストによって前提が異なる。

## キーバインドは `Ctrl+V` (両ホスト共通)

`Ctrl+Shift+V` は**端末側**のペーストバインド (Ghostty / WezTerm とも)。ターミナルがクリップボードの *テキスト* を bracketed paste で送るだけなので画像は届かない。Claude Code の画像ペーストは端末のペースト機構を使わず、キー入力を受けて自分でクリップボードコマンドを実行する実装のため、**素通しされる `Ctrl+V` が正解**。

## ubuntu (Wayland native)

`wl-paste` が `image/png` を直接返すため追加設定は不要。

## wsl-gentoo (WSLg) — `wl-paste` shim が必要

WSLg のクリップボードブリッジは Windows 側の `CF_PNG` を落とし、DIB を **`image/bmp` としてのみ**広告する。しかもその BMP は `BITMAPINFOHEADER.biCompression == 3` (`BI_BITFIELDS`) で、Claude Code が同梱する sharp/libvips はこれをデコードできない。Claude Code は先頭が `BM` のとき PNG 変換を試み、**失敗した例外を無言で握り潰す**ため、`Ctrl+V` を押しても画面上は完全に無反応になる。

```console
$ wl-paste -l
image/bmp                                    # image/png は出ない

$ wl-paste --type image/bmp | file -
/dev/stdin: PC bitmap, Windows 3.x format, 320 x 200 x 32, 3 compression, ...
```

対処として `hosts/wsl-gentoo.nix` で `~/.local/bin/wl-paste` に shim を置き、`image/png` を**追加で**広告して要求時に ImageMagick で変換する。既存の `image/bmp` 経路は触らないので、BMP を直接扱う他アプリの挙動は変わらない。`~/.local/bin` は PATH 上で `~/.nix-profile/bin` より前にあるため優先される。

Claude Code は貼り付けのたびに `sh -c` でクリップボードコマンドを起動するので、**shim を置けば Claude Code の再起動なしで効く**。

## 切り分け手順

**`/tmp/claude-1000/claude_cli_latest_screenshot.png` の有無と mtime を見る。** Claude Code は `saveImage` でここに書くため、`Ctrl+V` 直後にこのファイルができていれば**キーは届いている** (端末・キーバインドは無罪) と即断できる。中身が BMP なら本件。

Claude Code (2.1.235) が実行するコマンドチェーンは以下のとおり。手で流せばどの段で落ちるか特定できる。

```sh
# checkImage
xclip -selection clipboard -t TARGETS -o 2>/dev/null | grep -E "image/(png|jpeg|jpg|gif|webp|bmp)" \
  || wl-paste -l 2>/dev/null | grep -E "image/(png|jpeg|jpg|gif|webp|bmp)"

# saveImage
xclip -selection clipboard -t image/png -o > $f 2>/dev/null \
  || wl-paste --type image/png > $f 2>/dev/null \
  || xclip -selection clipboard -t image/bmp -o > $f 2>/dev/null \
  || wl-paste --type image/bmp > $f
```

診断スクリプトを貼り付けて流すときは、`\` の行継続の直後に**空行を入れない**こと。zsh が継続を打ち切り、`-Command` に引数が渡らないまま次行が別コマンドとして実行され、クリップボードと無関係な `command not found` / `exit=127` になる (Issue #133 で実際に誤診の原因になった)。

## 上流の状況

- [anthropics/claude-code#50552](https://github.com/anthropics/claude-code/issues/50552) — 逆アセンブル付きで同一原因を報告済みだが、修正されないまま **stale で NOT_PLANNED クローズ**
- #77102 (Ghostty + WSLg で同構成) / #36420 — いずれも重複扱いで自動クローズ
- #61609 — 唯一 open だが stale ラベル付き

2.1.235 には WSL 向け PowerShell フォールバック (`Clipboard::GetImage` → PNG → base64) が追加されており、単体では正常に動く。しかしチェーンの**最後**に置かれているため、WSLg では `wl-paste --type image/bmp` が先に成功してしまい**到達しない**。上流への報告は行わない方針。
