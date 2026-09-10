# East Asian Ambiguous 文字幅 (EAW)

glibc 2.39+ で `wcwidth()` が East Asian Ambiguous 文字 (△→○●■□▲ 等) に 1 を返すようになった (2.38 以前は `ja_JP` ロケールで 2 を返していた)。Unicode 標準 (UAX #11 §5「文脈が確立できない場合は narrow として扱う」) への準拠が理由。

## 現在の方針

**ターミナル系はすべて幅 1、Emacs GUI だけ幅 2。**

| レイヤー | 幅 | 実装 |
|---------|----|------|
| ターミナル (noctty / Ghostty 系) | 1 | uucode のテーブル。**設定で変更不可** |
| glibc `wcwidth()` (zsh / readline / tmux) | 1 | 素の `ja_JP.utf8` (`/usr/lib/locale`) をそのまま使う |
| Claude Code TUI | 1 | Node.js の標準 Unicode 幅テーブル |
| Emacs GUI (WSLg) | 2 | `modules/emacs/site-lisp/eaw-console.el` (locale-eaw 由来) |
| Emacs TUI (`emacs -nw` / `emacsclient -t`) | 1 | `use-default-char-width-table` で Emacs 既定のテーブルに戻す |

以前は [locale-eaw](https://github.com/hamano/locale-eaw) EAW-CONSOLE を使い、glibc (`LOCPATH` + カスタムロケール) / WezTerm (`cell_widths`) / Emacs (`char-width-table`) の 3 レイヤーを幅 2 に揃えていた (#64)。メインターミナルを WezTerm から noctty (Ghostty の Windows port fork) に移した時点でこの前提が崩れたため、#71 でターミナル側の 2 レイヤーを撤去した。

## なぜターミナル側を幅 2 に揃えられないか

Ghostty 系は文字幅の単一情報源として `uucode` を使い、Ambiguous を幅 1 に固定している。ユーザー設定で上書きする手段がない。

- `src/build/uucode_config.zig` の `computeWidth` が `data.width = @min(2, data.wcwidth_standalone)`。uucode 側の `wcwidth_standalone` は Wide (W) / Fullwidth (F) のみ 2 で、Ambiguous (A) は 1。
- 設定は `grapheme-width-method` (`unicode` / `legacy`) のみ。これはグラフェムクラスタの幅計算方式の切替で、Ambiguous の判定には効かない。libc `wcswidth` を使う保証もない (実装コメントに明記)。そもそも Windows 側プロセスなので WSL の glibc / `LOCPATH` は参照できない。
- WezTerm の `cell_widths` / `treat_east_asian_ambiguous_width_as_wide` に相当する設定は存在しない。

したがって glibc 側だけ幅 2 に強制すると、**zsh (p10k の右プロンプト・折り返し)、readline、tmux が計算するカーソル位置とターミナルの実セル位置が 1 つずつずれる**。noctty 運用ではターミナルに合わせて幅 1 に統一するのが唯一整合する選択肢になる。

実測 (glibc 2.43 / Gentoo):

```text
LOCPATH あり (旧構成): △→○●■□▲ = 2,  ─│ = 1,  あ = 2   ← ターミナルとずれる
LOCPATH なし (現構成): △→○●■□▲ = 1,  ─│ = 1,  あ = 2   ← ターミナルと一致
```

## Emacs GUI だけ幅 2 を維持している理由

Emacs GUI は WSLg 上の独立したレンダラで、ターミナルのセルとは無関係に自前で文字幅を決める。日本語文書の可読性 (△○● が細くならない) を取れるので幅 2 のまま維持している。

**前提**: Emacs は `wcwidth()` を見ない。日本語の言語環境では CJK 用の `char-width-table` を使い、Ambiguous を**罫線 (`─│`) まで含めてすべて幅 2** にする。`eaw-console.el` はこのうち罫線だけを幅 1 に戻す (EAW-CONSOLE 方式) ものであって、「読み込まなければ幅 1 になる」わけではない。実測 (Emacs 31.1, `LANG=ja_JP.UTF-8`):

```text
既定 (何もしない):              △→○●■ = 2,  ─│ = 2,  あ = 2
eaw-console.el を読む:          △→○●■ = 2,  ─│ = 1,  あ = 2
(use-default-char-width-table): △→○●■ = 1,  ─│ = 1,  あ = 2   ← noctty と一致
```

設計上の注意点:

- **フレーム種別で切り替える**: `char-width-table` はプロセスグローバルでフレームごとに切り替えられない。`init.el` の `my/apply-char-width-table` が、GUI フレームなら `eaw-console.el` を読み込み、tty フレームなら `use-default-char-width-table` で既定 (Ambiguous = 幅 1) に戻す。tty で何もしないと罫線まで幅 2 になり、端末とのずれはむしろ大きくなる。
- **daemon**: 初期化時点では `display-graphic-p` が nil なので、フォント設定 (`my/set-font-linux`) と同じく `after-make-frame-functions` に回す。GUI と tty のフレームが同居する場合は後から作ったフレームの方針で上書きされる (プロセスグローバルなので避けられない)。
- **読み込み順**: `set-language-environment "Japanese"` が `char-width-table` をリセットするため、`eaw-console.el` はその後に読み込む。
- **フォント**: `set-fontset-font` はフォールバック機構で、プライマリフォントにグリフがあれば無視される。UDEV Gothic NF は △→ に半角グリフを持つので、全角グリフを持つ **UDEV Gothic JPDOC をプライマリフォントにする**必要がある (`init.el` の `my/set-font-linux`)。

## ターミナル側での見え方

noctty では Ambiguous はセル 1 個分として扱われるが、グリフの描画は文字ブロックで挙動が分かれる。

| 文字 | ブロック | `isSymbol` | セル幅 | 描画 |
|------|---------|-----------|--------|------|
| `→` | Arrows (U+2190..U+21FF) | true | 1 | `.fit` 制約で 1 セルに縮小 |
| `△○●■□▲` | Geometric Shapes (U+25A0..U+25FF) | false | 1 | 無制約。全角グリフが隣のセルに視覚的にはみ出す |

Geometric Shapes は Ghostty の `computeIsSymbol` の対象ブロックに入っていないため制約 `.none` になる。**カーソル位置・表・TUI のレイアウトは崩れない**ので、見た目のはみ出しは許容している (レイアウト整合性を見た目より優先する方針)。

## 復活させる場合

メインターミナルを WezTerm 系 (`cell_widths` を持つ実装) に戻すなら、glibc + ターミナルの 2 レイヤーを再導入することになる。撤去した `modules/locale-eaw/` (localedef + `LOCPATH`、`UTF-8-EAW-CONSOLE.gz`、`eaw-console-wezterm.lua`) と `modules/wezterm/wezterm.lua` の `cell_widths` 設定は git 履歴 (#71 の PR) から復元できる。その際は Claude Code TUI が幅 1 前提であることに注意 (`●` U+25CF / `⎿` U+23BF を個別に幅 1 へ戻す例外が必要 — #65)。

## 参考

- [locale-eaw](https://github.com/hamano/locale-eaw) / [UDEV Gothic](https://github.com/yuru7/udev-gothic)
- [UAX #11 East Asian Width](https://www.unicode.org/reports/tr11/)
- #64 (locale-eaw 導入) / #65 (Claude Code TUI 互換) / #71 (noctty 移行に伴う撤去)
- 解説記事: [glibc 2.39+ で半角になった△→○●を locale-eaw で直す](https://zenn.dev/nanasess/articles/glibc-eaw-ambiguous-width-fix)
