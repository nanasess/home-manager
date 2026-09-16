# ibus-skk (SKK 入力メソッド)

設定: `pkgs/ibus-skk.nix` + `modules/ibus-skk/`（`nanasess@ubuntu` と NixOS `k-2`。エンジン登録経路はホストごとに異なる、後述）。Ubuntu では apt 版 1.4.3 を Nix ビルドの 1.4.4 で置き換えている。

## apt 版 1.4.3 は ▼変換中に母音を打つと確定文字列が消える

`▽じょうき` → `SPC` → `▼上記` の状態から `C-j` を省いてローマ字入力を続けたときの挙動:

| 続けて打つ文字 | ddskk | ibus-skk 1.4.3 |
|---|---|---|
| `あ`（母音・1 打鍵） | 「上記あ」 | **「あ」のみ**（上記が消える） |
| `は`（子音+母音・2 打鍵） | 「上記は」 | 「上記は」（正常） |

原因は libskk ではなく ibus-skk 側。1 回の `process_key_event` 中に `commit_text` が 2 回呼ばれ、クライアントには最後の 1 回しか反映されない。

- `src/engine.vala:142` — `context.candidates.selected` シグナル内で `poll_output()` → `commit_text("上記")`
- `src/engine.vala:441` — `process_key_event` 末尾で `poll_output()` → `commit_text("あ")`

母音は 1 打鍵で仮名が確定するので同一イベント内で 2 回、子音+母音はイベントごとに 1 回ずつになるため、母音のときだけ壊れる。上流 1.4.4 の `Don't split sending CommitText when auto-start conversion [#71]` がシグナル側の `commit_text` を削除して修正済み。

libskk 側は 1.0.5 の時点で正しく動作する（`SelectStateHandler` が `candidates.select()` → `state.reset()` → `return false` し、`Context.process_key_event_internal` のループが `NoneStateHandler` で同じキーを再処理する）。切り分けには `gir1.2-skk-1.0` を展開して python から `Skk.Context` を直接叩くのが早い。

## IBus のコンポーネント探索は XDG を一切見ない

(Ubuntu の話。NixOS (k-2) は `i18n.inputMethod.ibus.engines` に `pkgs/ibus-skk.nix` を
渡すだけで、`ibus-with-plugins` が `IBUS_COMPONENT_PATH` を束ねてくれる。`meta.isIbusEngine`
がその型チェックの印。辞書設定の dconf は `modules/ibus-skk/default.nix` で両ホスト共通。)

`ibus_registry_load()` の実装:

```c
envstr = g_getenv ("IBUS_COMPONENT_PATH");
if (envstr) {
    /* ← 設定されていれば「これだけ」を探索 */
} else {
    dirname = g_build_filename (IBUS_DATA_DIR, "component", NULL);  /* /usr/share/ibus/component のみ */
}
```

`g_get_user_data_dir()` は FIXME でコメントアウトされている。そのため Ghostty / pavucontrol で使っている「`XDG_DATA_HOME` に置く」回避策は効かない。

一方 `ibus-daemon` は GNOME では systemd ユーザーサービス (`org.freedesktop.IBus.session.GNOME.service`) として起動するため `~/.config/environment.d/` が届く。`systemd.user.sessionVariables.IBUS_COMPONENT_PATH` でエンジンを登録している。

**`IBUS_COMPONENT_PATH` を設定すると `/usr/share/ibus/component` が探索対象から外れる**（上記の `else` 分岐）。mozc など他エンジンが消えるので、必ず併記すること。

## apt 版は削除が必須

component 名 (`org.freedesktop.IBus.SKK`) とエンジン名 (`skk`) が apt 版と同一なので、両方が探索対象にあると二重登録になる。`sudo apt remove ibus-skk` すること。`check-system-packages` が競合として検出する。

エンジン名が同一なので、`dconf` の辞書設定 (`desktop/ibus/engine/skk`、`hosts/ubuntu.nix`) はそのまま引き継がれる。`encoding=` の受け渡し (`engine.vala` → `Skk.SkkServ`) も 1.4.4 + libskk 1.1.0 で変わっていない。

## layout は default に固定している

上流の `skk.xml.in.in` は `<layout>jp</layout>` で、SKK を有効にすると JIS 配列が強制される。Ubuntu 側では `/usr/share/ibus/component/skk.xml` を手で `default` に書き換えて運用していた（`dpkg --verify ibus-skk` が改変を検出。2026-03-06）ため、`pkgs/ibus-skk.nix` の `postPatch` でその状態を宣言的に再現している。

## 反映手順

`home-manager switch` だけでは既存セッションに `IBUS_COMPONENT_PATH` が届かない。

```bash
sudo apt remove ibus-skk
# 推奨: 再ログイン (systemd --user が environment.d を読み直す)
```

現在のセッションを維持したい場合は、`environment.d` を読み直してから IBus のユニットを再起動する。

```bash
systemctl --user daemon-reload
systemctl --user restart org.freedesktop.IBus.session.GNOME.service
```

`systemctl --user import-environment IBUS_COMPONENT_PATH` は**使えない**。`systemd.user.sessionVariables` が書き出すのは `environment.d/10-home-manager.conf` だけでシェルには値が入らず、`import-environment` は「クライアント側で設定済みの値」を取り込むコマンドだからである。

`ibus restart` も避ける。D-Bus 経由で daemon に自己 re-exec を要求するもので、re-exec は environ を引き継ぐため新しい値が反映されない (未検証だが、ユニットごと再起動すれば確実に manager 環境を継承する)。

## sudo のパスワード入力中は US 配列に切り替える

SKK をかなモードにしたまま `sudo` を打つとパスワードが仮名に化けるので、
`modules/ibus-skk/default.nix` の zsh 関数 `sudo` がプロンプトの間だけ IBus の
グローバルエンジンを `xkb:us::eng` にし、終了後 (Ctrl-C 含む) に元へ戻す。

- `ibus engine xkb:us::eng` は使えない。IBus CLI は xkb エンジンへ切り替えるときに
  `setxkbmap` を spawn するため、Wayland セッション (setxkbmap 無し) では
  `Execute setxkbmap failed` で終了コード 1 になる。IBus 自身のバス (`ibus address`) に
  `gdbus call ... org.freedesktop.IBus.SetGlobalEngine` を投げれば GNOME Shell 配下でも
  切り替わる (k-2 で確認)。読み取りの `ibus engine` は問題ない。
- GNOME Shell はエンジンが外部から変わっても入力ソース表示を追従させない
  (`ibusManager.js` の `_engineChanged` は `_currentEngineName` を更新するだけ)。
  プロンプトの間だけの一時的な切替なので実害はない。
- 元に戻すとき skk エンジンは作り直される (`SetGlobalEngine` は旧エンジンを破棄する)。
  ibus-skk は `initial_input_mode` をコンストラクタでしか読まないので、sudo 前が
  かなモードでも sudo 後は `initial-input-mode = 3` (latin) に戻る。
- `sudo -n true` が通る (タイムスタンプ有効) ときはプロンプトが出ないので切り替えない。
  IBus が無い環境や既に xkb エンジンのときも素通し。
