# Chrome のタブ移動キーバインド (xremap)

設定: `modules/xremap/`（`nanasess@ubuntu` のみ）。Chrome にフォーカスがある時だけキーを置換する。

| キー | Chrome での動作 |
|---|---|
| `Ctrl+H` | 前のタブ (`Ctrl+PageUp`) |
| `Ctrl+L` | 次のタブ (`Ctrl+PageDown`) |
| `⌘+L` | アドレスバー (`Ctrl+L`) |

## Chrome 自体にキーバインド変更機能はない

`chrome://settings` にも `chrome://flags` にも項目がなく、タブ移動は `Ctrl+PageUp` / `Ctrl+PageDown` 固定。実現手段は 2 つあり、xremap を採った。

| 方式 | 難点 |
|---|---|
| Chrome 拡張 (Shortkeys 等) | コンテンツスクリプト方式のため `chrome://` 系ページ・新規タブページ・ページ読込前で効かない。`Ctrl+L`（アドレスバー）を奪えるかも不確実。宣言的管理にも乗せづらい |
| **xremap** | evdev/uinput レベルで置換するので Chrome に届く時点ですでに `Ctrl+PageUp`。全コンテキストで効く。ただし `input` グループ加入という root 作業とセキュリティ上の代償を伴う |

副作用として Chrome 内で `Ctrl+H`（履歴）と `Ctrl+L`（アドレスバー）は使えなくなる。アドレスバーは `⌘+L` に逃がしてあり、Chrome 標準の `Alt+D` / `F6` も残る。

## XKB レイヤの変換 (ctrl:nocaps / altwin) は xremap には見えない

**最重要の落とし穴**。この環境の `xkb-options` は `['ctrl:nocaps', 'altwin:swap_lalt_lwin']`。

```text
物理キー → evdev (xremap はここを見る) → XKB (ctrl:nocaps 等) → アプリ
```

XKB は evdev より上のレイヤなので、`ctrl:nocaps` による Caps Lock → Ctrl の変換は xremap からは見えない。実際、xremap のデバッグログには **`KEY_LEFTCTRL` が一度も現れず `KEY_CAPSLOCK` だけ**が出る。素直に `C-h` と書いても永久にマッチしない（この症状が最初の実装で発生した）。

`modules/xremap/default.nix` では Chrome スコープの `modmap` で `capslock: leftctrl` に変換し、その出力を `keymap` に通して解決している（README「the output of `modmap` goes through `keymap`」）。`application` で Chrome に限定してあるので他アプリの入力経路は変わらず、アプリ判定が失敗しても capslock がそのまま流れて XKB が Ctrl にするだけなので縮退動作は従来どおり。

同じ理由で **`⌘` は evdev では `KEY_LEFTMETA`**（xremap の表記では `Super-` / `Win-`）。`altwin:swap_lalt_lwin` で XKB 上は Alt になっているが、xremap はその手前で消費するので影響を受けない。実測でも `KEY_LEFTALT` は一度も現れない。

切り分けはデバッグログが最速。サービスを止めて手動起動する:

```bash
systemctl --user stop xremap.service
RUST_LOG=debug xremap --watch ~/.config/xremap/config.yml 2>&1 | tee /tmp/xremap.log
```

`=> 1: KEY_XXX` が全キーイベント（`1`=押下 / `0`=解放 / `2`=オートリピート）。`application-client:` 行が一度も出ない場合は、**キー自体が一致していない**（xremap はキー + 修飾キーが一致して初めてアプリ判定を呼ぶ）。

## GNOME Wayland ではアプリ判定に Shell 拡張が要る

xremap は「フォーカス中アプリ」を知らないと `application.only` を判定できない。X11 なら xremap 自身が `WM_CLASS` を読めるが、Wayland にはその汎用 API がない。GNOME では xremap の Shell 拡張 (`xremap@k0kubun.com`) が D-Bus (`com.k0kubun.Xremap`) で WMClass を渡す。

**Chrome 151 は Ubuntu 24.04 でネイティブ Wayland 動作**（`xprop` / `xlsclients` に現れない）なので、この経路が必須。

- nixpkgs の `pkgs.xremap` 既定は **wlroots build**。`override { withVariant = "gnome"; }` で gnome feature 版に差し替える（variant 名は nixpkgs の `pkgs/by-name/xr/xremap/package.nix` の `variants` 参照）
- 拡張は `xdg.dataFile` で `~/.local/share/gnome-shell/extensions/` へリンクする。[Nix GUI アプリのランチャー登録](nix-desktop-integration.md) と同じ `XDG_DATA_DIRS` 問題がここにも当てはまる
- `dconf` の `org/gnome/shell` `enabled-extensions` は**配列まるごと置換**。Ubuntu 既定の `ding` / `ubuntu-dock` / `tiling-assistant` を併記しないと消える
- WMClass の実測は `busctl --user call org.gnome.Shell /com/k0kubun/Xremap com.k0kubun.Xremap WMClasses`。GNOME Wayland では `xremap --list-windows` は使えない
- キー名は `parse_key()` が大文字化して `KEY_` を補うので `pageup` / `pagedown` でよい

## 権限設定は root 作業として残る

home-manager では宣言できない。`/dev/uinput` は既定で `root:root 0600`、`uinput` モジュールも未ロード。

```bash
sudo gpasswd -a nanasess input
echo 'KERNEL=="uinput", GROUP="input", TAG+="uaccess", MODE:="0660", OPTIONS+="static_node=uinput"' \
  | sudo tee /etc/udev/rules.d/99-input.rules
echo uinput | sudo tee /etc/modules-load.d/uinput.conf
sudo udevadm control --reload-rules && sudo udevadm trigger
sudo modprobe uinput
```

最後の `modprobe` を省かないこと。`modules-load.d` は `systemd-modules-load.service` が早期ブートで処理する仕組みで、ファイルを置いた時点ではロードされない。ただし**この T2 Mac のカーネルでは `uinput` は組み込み**で、`/dev/uinput` が静的ノードとして最初から存在する（`lsmod | grep uinput` は空、`/sys/devices/virtual/misc/uinput` は存在）。つまり本機では `modules-load.d` も `modprobe` も実質 no-op で、効いているのは udev ルールと `input` グループだけ。手順は他機での再現のために残してある。

**セキュリティ上のトレードオフ**: `input` グループ加入は、このユーザーアカウントに全アプリのキー入力を読む権限を与える（xremap の `doc/running_without_sudo.md` も明記）。画面ロック中もリマップは有効。承知のうえで採用している。「セキュリティ向上のため」と称してこの構成を勝手に変更しないこと。

## 反映手順

`home-manager switch` 後に**再ログインが必要**。理由が 2 つある。

- `input` グループの追加はログインし直さないと反映されない
- **Wayland では GNOME Shell を再起動できない**（X11 の `Alt+F2` → `r` に相当する手段がない）ため、拡張のロードにログインし直しが要る

権限が無い間、`xremap.service` は `Failed to prepare input devices: No device was selected!` で 3 秒ごとに再起動を繰り返す。これは想定内で、権限が付けば解消する。

## 設定変更は `--watch=config,device` で反映される

`ExecStart` が参照するのは安定パス `~/.config/xremap/config.yml` なので、**設定内容が変わってもユニットファイルは変化せず、home-manager はサービスを再起動しない**。裸の `--watch` は device 監視のみ（xremap の CLI 定義が `default_missing_value = "device"`）なので、config も監視対象に含めておかないと `home-manager switch` のたびに `systemctl --user restart xremap.service` が必要になる。

home-manager のシンボリックリンク差し替えでも検知できる。`ConfigWatcher` が親ディレクトリを `IN_CREATE | IN_MOVED_TO` で監視し、ファイル名を照合して watch を張り直す実装になっている（`src/platform_linux/config_watcher.rs`）。

## `exact_match` は既定の false のままにしてある

`false` だと `Ctrl+Shift+H` のように修飾キーが増えた組み合わせにもマッチするが、**余った修飾キーは解放されず保持される**（`event_handler.rs` の `extra_modifiers.retain(|key| ... && !extra_modifiers_pressed.contains(key))`）。つまり出力は `Ctrl+Shift+PageUp` = Chrome のタブ並び替えになる。`H` / `L` のニーモニックと整合する有用な副産物で、これで潰れる Chrome 標準ショートカットも無い。`exact_match: true` を足すとこの動作が消えるだけなので、レビューで指摘されても意図的な選択であることを確認してから判断する。

## 動作確認

```bash
systemctl --user status xremap.service
gnome-extensions info xremap@k0kubun.com          # State: ACTIVE か
busctl --user call org.gnome.Shell /com/k0kubun/Xremap com.k0kubun.Xremap WMClasses
```
