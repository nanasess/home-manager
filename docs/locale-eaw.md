# East Asian Ambiguous 文字幅 (locale-eaw)

glibc 2.39+ で `wcwidth()` が East Asian Ambiguous 文字 (△→○●■□▲ 等) に 1 を返すようになり、日本語環境で半角表示される問題に対処。[locale-eaw](https://github.com/hamano/locale-eaw) EAW-CONSOLE を使い、全レイヤーで文字幅を統一する。

## メカニズム

```text
locale-eaw EAW-CONSOLE
├── glibc wcwidth()     -- LOCPATH でカスタムロケール適用 (△→=2, ─│=1)
├── WezTerm cell_widths -- eaw-console-wezterm.lua で同じ幅テーブルを適用
└── Emacs char-width-table -- eaw-console.el で同じ幅テーブルを適用

UDEV Gothic JPDOC (全角グリフ提供)
├── WezTerm -- プライマリフォント (NF は Nerd Font 用 fallback)
└── Emacs   -- プライマリフォント (set-fontset-font はフォールバック機構のため不可)
```

## 設計上の注意点

- **ロケール生成**: `localedef` でユーザー空間 (`~/.local/share/locale/ja_JP.utf8`) にコンパイル。ロケール名は `ja_JP.utf8` のまま、charmap だけ `UTF-8-EAW-CONSOLE` を使用。`LOCPATH` で既存システムロケールより優先。
- **WezTerm**: Windows 側で動作するため、Linux のフォントや LOCPATH は参照不可。`font_dirs` で JPDOC フォントを、`dofile` で cell_widths 設定を Windows 側からロード。
- **Emacs フォント**: `set-fontset-font` はフォールバック機構であり、プライマリフォントにグリフがある場合は無視される。そのため JPDOC をプライマリフォントとして設定する必要がある。
- **Emacs char-width-table**: `set-language-environment "Japanese"` が `char-width-table` をリセットするため、`eaw-console.el` はその後に読み込む。
