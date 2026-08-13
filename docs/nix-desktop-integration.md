# Nix GUI アプリのランチャー登録

GNOME セッションの `XDG_DATA_DIRS` は `/usr/local/share:/usr/share:/var/lib/snapd/desktop` だけで、**`~/.nix-profile/share` を含まない**。そのため nixpkgs が提供する `.desktop` はランチャー（GNOME アプリ一覧 / Walker）から見えない。ログインシェルの `XDG_DATA_DIRS` には入っており端末からは起動できてしまうため気づきにくい。

対処は `XDG_DATA_HOME`（`~/.local/share/applications/`）へ自前の `.desktop` を置くこと。`Exec` と `Icon` もセッション側では解決できないので、**`~/.nix-profile` 経由のフルパス**で指定する（store パス直書きは更新のたびに切れる）。

先例: Ghostty (`hosts/ubuntu.nix`)、pavucontrol (`modules/bluetooth-audio/default.nix`)。

根治策として `targets.genericLinux.enable = true` で `XDG_DATA_DIRS` ごと直す手もあるが、セッション全体に影響するため未採用。

## アイコンも同じ理由で解決できない

`.desktop` を `~/.local/share/applications/` に置いてもアプリ一覧に**アイコンだけ出ない**ことがある。`Icon=<name>` のテーマ検索も `XDG_DATA_DIRS` 依存で、GTK の検索パスは `~/.local/share/icons` → `~/.icons` → `$XDG_DATA_DIRS/*/icons` の順。nix profile がここに無いので `~/.nix-profile/share/icons/hicolor/...` は引かれない。

対処は `xdg.dataFile` でアイコンを `~/.local/share/icons/hicolor/<size>/apps/` にリンクすること。`hosts/ubuntu.nix` の `iconLinks` ヘルパーが Ghostty と Emacs 用にこれを行っている。

- `Icon=` に絶対パスを書いてもよい (pavucontrol はこの方式) が、解像度が固定になる。複数サイズを張るほうが HiDPI で有利
- 張るサイズは「パッケージが持っていて、かつ `/usr/share/icons/hicolor/index.theme` が定義しているもの」だけにする。未定義のディレクトリ (Ghostty の `1024x1024` や `*@2`) は張っても引かれない
- `index.theme` 自体は nix profile 側に無くてよい。テーマ定義は `/usr/share/icons/hicolor/index.theme` が提供し、ディレクトリ探索は全ベースディレクトリに適用される

**apt 版が同名アイコンを持つケースに注意**: Emacs は apt の emacs-common が `/usr/share/icons/hicolor` に `emacs.png` を置くため、未配置でも表示されてしまう。apt 版に依存した偶然なので、nixpkgs 側 (実際に起動する `emacs30-pgtk`) を明示的に優先させている。

検証は GTK に実際に引かせるのが確実 (gnome-shell と同じ `XDG_DATA_DIRS` を再現する):

```bash
env -u GI_TYPELIB_PATH XDG_DATA_DIRS="/usr/local/share/:/usr/share/:/var/lib/snapd/desktop" \
  /usr/bin/python3 -c 'import gi; gi.require_version("Gtk","3.0"); from gi.repository import Gtk;
i=Gtk.IconTheme.new().lookup_icon("com.mitchellh.ghostty",128,0); print(i.get_filename() if i else "NOT FOUND")'
```

`/usr/bin/python3` を使うこと (Nix の python3 では GI typelib を拾えず落ちる)。

**Walker は対象外**: nixpkgs の walker は `bin/walker` だけで `share/` を持たず、上流 (`abenz1267/walker`) にもアプリアイコンが存在しない (`v2.17.0` / 旧 Go 版 `v0.13.26` ともスクリーンショット画像のみ)。パス問題ではないので上記の方法では直せない。必要なら application id `dev.benz.walker` で `.desktop` を作り、システムテーマの汎用アイコン (`system-search` 等) を代用する。

**IBus エンジンには通用しない**: IBus のコンポーネント探索は `XDG_DATA_DIRS` も `XDG_DATA_HOME` も見ない。詳細は [ibus-skk (SKK 入力メソッド)](ibus-skk.md) を参照。
