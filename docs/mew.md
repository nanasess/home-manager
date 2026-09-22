# Mew (Emacs メーラ) — Gmail XOAUTH2 + 1Password

`modules/emacs/init.el` の「Email (Mew)」セクションと `pkgs/mew.nix` の背景・手順。
旧 dotfiles (`~/.config/dotfiles` の `.emacs.d/.mew.d/`、2026-04 に削除) からの再導入で、
秘密情報を 1Password に集約して公開リポジトリに置ける形にした。

## 構成

| 層 | 管理 | 備考 |
|---|---|---|
| elisp (Mew 本体) | elpaca (`use-package mew`、上流 kazu-yamamoto/Mew) | MELPA の recipe (`elisp/*.el` `etc` `info/*.info*`) を継承。nixpkgs の `emacsPackages.mew` は elisp のみで `bin/` を含まないので使わない |
| 外部コマンド (`mewl` `mewencode` `incm` `cmew` `smew` `mew-pinentry`) | Nix (`pkgs/mew.nix`、`modules/emacs/default.nix` の `home.packages`) | `bin/` だけを configure + make。`cmew` / `smew` は Ruby + sqlite3 gem 付きの ruby に shebang を差し替える。nixpkgs の `mew` は無関係な dmenu の Wayland 移植 |
| 秘密情報 | 1Password (`op://Personal/Mew Gmail XOAUTH2/…`) | Emacs からは `op read` で実行時に解決 (`my/op-read`)。init.el に残るのは op:// 参照だけ |
| メール本体 / トークン | `~/Mail` (管理外) | IMAP キャッシュ、下書き、`.mew-passwd.gpg` (OAuth2 トークン) |

elisp と bin は **同じ上流コミット** に固定する (`modules/emacs/elpaca.lock` の `mew` の `:ref` と
`pkgs/mew.nix` の `rev`)。更新時は両方を揃える。

## 秘密情報の流れ

```
1Password アイテム "Mew Gmail XOAUTH2" (vault: Personal)
  ├─ client-id      ─┐  mew-init-hook (my/mew-setup-oauth2)
  ├─ client-secret  ─┘   → mew-oauth2-client-id / mew-oauth2-client-secret
  └─ password       ──── mew-read-passwd の advice (my/mew-read-passwd-from-op)
                          → Mew の master password → ~/Mail/.mew-passwd.gpg を gpg で復号
                                                      (OAuth2 のアクセス / リフレッシュ トークン)
```

- `op read` は **Emacs 起動時ではなく `M-x mew` の初回** に走る (hook / advice で遅延)。
  結果は `my/op-read-cache` にセッション内キャッシュするので 1Password の承認は 1 度で済む。
- `op read` が失敗 (1Password 未起動 / ロック中 / アイテム無し) すると `M-x mew` が
  `user-error` で止まる。1Password 側を直してもう一度 `M-x mew` すればよい。
  フィールドが未入力でも `op read` は exit 0 で空文字を返すので、`my/op-read` が空を弾く。
- wsl-gentoo の `op` は `~/.local/bin/op` ラッパー → Windows 側 `op.exe`。Emacs の
  `exec-path` に `~/.local/bin` が入っているので Emacs からも同じ経路で解決できる。
- k-2 は `programs._1password.enable` (NixOS) が setgid wrapper 付きの `op` を systemPackages に
  入れる。home-manager 側で `_1password-cli` を足すと wrapper を隠して GUI 連携が壊れるので足さない。
  ubuntu は apt の `1password-cli` (aptPackages 未宣言、要確認)。

### 認可 URL に access_type=offline / prompt=consent を足す

上流 `mew-oauth2-get-auth-code` の認可 URL には `access_type=offline` が無い。Google はデスクトップ型
クライアントには黙ってリフレッシュ トークンを返すが、「ウェブ アプリケーション」型には
`access_type=offline` が無いと返さない。初回導入時 (2026-09-21) の実測では両トークン (IMAP / SMTP) の
`:refresh_token` が nil で、アクセス トークンの期限 (約 1 時間) ごとにブラウザ認可が再発する状態だった。
init.el では `mew-oauth2-get-auth-code` を `:override` で置き換え、`&access_type=offline&prompt=consent` を
足している (`my/mew-oauth2-get-auth-code`、それ以外は上流のコピー)。`prompt=consent` は、保存済み
トークンを失って再認可するときにも必ずリフレッシュ トークンを発行させるため (Google は 2 回目以降の
同意ではこれが無いと返さない)。

このオーバーライドは上流本体のコピーなので、**Mew を更新したら差分が開いていないか確認する**。
上流 66261fb (PR #235) は認可 URL に `state` を足し、リダイレクト ハンドラが `state` の一致しない
認可コードを `400 Bad Request` で弾くようにした (RFC 6749 10.12)。`mew-oauth2-state` の生成を
落としたオーバーライドを当てると、ブラウザ認可が毎回失敗する (`mew-oauth2-state` が nil のまま
ハンドラの検証に入るため)。同じコミットで `unwind-protect` によるリッスン ソケットの後始末も
入ったので、こちらも取り込んである。

### トークン取得 / 更新は上流 (curl) に任せる

上流 `mew-oauth2.el` はトークン取得 (認可コード → アクセス トークン) と更新 (リフレッシュ トークン →
アクセス トークン) を curl で行う。6.11 の途中まではパラメータを `curl --data PARAMS` と
コマンドライン引数に載せており、client secret / refresh token / 認可コードが同一ホストの他ユーザーから
`/proc/<pid>/cmdline` 経由で読めた (CodeRabbit の指摘、CWE-214)。init.el はこれを
`url-retrieve-synchronously` 版 (`my/mew-oauth2-post`) への `:override` で回避していたが、
**上流 66261fb (PR #235) が `mew-oauth2-post` を入れて解決したのでオーバーライドは削除した**。
上流版は `mew-temp-dir` にモード 600 の一時ファイルを作って本文を書き、`--data @file` で渡し、
終わったら消す。値のエンコードも `mew-oauth2-params` が `url-hexify-string` で行うので、
`+` や `&` を含む client secret も壊れない (自前版はそこまで見ていなかった)。

その代わり `curl` への実行時依存は残る。Mew は `mew-prog-curl` (既定 `"curl"`) を
`mew-which-exec` で `exec-path` から探し、無ければ `"curl does not exist"` と表示してトークン取得を
諦める。wsl-gentoo は portage の、NixOS / Ubuntu は既定のシステム `curl` を使う (Nix では
明示していない)。

上流へ還元する価値が残るのは `access_type=offline` / `prompt=consent` (または追加パラメータ用の変数)
の 1 点。

### なぜ master password 方式か

Mew の XOAUTH2 (`mew-oauth2.el`、6.10 以降) はトークンを「Mew のパスワード機構」
(`mew-passwd-*`) に hash-table として預ける。永続化されるのは `mew-use-master-passwd t` +
`mew-master-passwd-type 'master` のときだけで、`~/Mail/.mew-passwd.gpg` に gpg の対称暗号
(AES) で保存される。もう一つの `'auth-source` 方式は `:secret` に文字列しか返せず hash-table を
扱えないため、**毎回ブラウザ認可** になる (コード読解による。auth-source 方式は未検証)。

旧 dotfiles は `mew-use-master-passwd nil` で運用しており、Emacs を再起動するたびに
ブラウザ認可が必要だった。今回は master password を 1Password から供給することで、
認可はブラウザ 1 回きり・以後プロンプトなしにしている。

gpg 2.1 以降では Mew が `--pinentry-mode loopback` を使い、読み込み前に
`gpg-connect-agent CLEAR_PASSPHRASE` でエージェントのキャッシュを消すため、パスフレーズは
必ず `mew-read-passwd` を通る (pinentry の GUI は出ない)。advice はそこに掛けている。

## セットアップ

### 1. Google Cloud の OAuth クライアント

<https://console.cloud.google.com/apis/credentials> で「OAuth クライアント ID」を作成する。

- アプリケーションの種類: **デスクトップ アプリ** (ループバック `http://localhost:<port>` への
  リダイレクトがポート未登録で許可される。Mew は `oauth2-redirect-port` = 28080 で待ち受ける)。
  「ウェブ アプリケーション」型でも動くが、承認済みリダイレクト URI に `http://localhost:28080` を
  登録する必要がある
- OAuth 同意画面: Google Workspace の組織なら **内部** にすると審査不要
- スコープ: `https://mail.google.com/` (Mew の `mew-oauth2-resource-url` 既定)
- クライアント ID とクライアント シークレットを控える

### 2. 1Password アイテム

vault `Personal` に `Mew Gmail XOAUTH2` (Login) を作り、以下のフィールドを持たせる。
`password` は `op item create --generate-password` で自動生成し、人が知る必要はない。

| フィールド | 型 | 内容 |
|---|---|---|
| `client-id` | text | 手順 1 のクライアント ID |
| `client-secret` | concealed | 手順 1 のクライアント シークレット |
| `password` | password | Mew の master password (自動生成) |

参照は init.el の `my/mew-op-item` (`op://Personal/Mew Gmail XOAUTH2`)。アイテム名や vault を
変えたらそこも直す。

作成例 (Linux 側の `/usr/bin/op`。wsl-gentoo の `~/.local/bin/op` ラッパー経由だと
op.exe が stdin のテンプレートを "invalid JSON in piped input" で受け取れない):

```bash
jq -n '{title:"Mew Gmail XOAUTH2", category:"LOGIN", fields:[
  {id:"password", type:"CONCEALED", purpose:"PASSWORD", label:"password", value:""},
  {id:"client-id", type:"STRING", label:"client-id", value:""},
  {id:"client-secret", type:"CONCEALED", label:"client-secret", value:""}]}' > /tmp/mew-item.json
/usr/bin/op item create --vault Personal --generate-password='letters,digits,32' --template /tmp/mew-item.json > /dev/null
rm /tmp/mew-item.json
```

### 3. 旧 `~/Mail/.mew-passwd.gpg` の退避

旧環境 (2024-09) の `.mew-passwd.gpg` が残っていると、旧 master password でしか復号できず
`Master password is wrong!` を繰り返す。新しい master password で作り直させるため退避する
(削除はしない)。

```bash
mv ~/Mail/.mew-passwd.gpg ~/Mail/.mew-passwd.gpg.2024-09-04
```

### 4. 初回起動

`home-manager switch` 後に Emacs を再起動し (elpaca が Mew を取得・ビルドする)、`M-x mew`。

1. 1Password の承認ダイアログ (client-id / client-secret / password の順に `op read`)
2. ブラウザで Google の認可画面が開く → 許可 → `http://localhost:28080/?code=…` に戻り、
   Emacs 側のリスナが認可コードを受け取る ("Mew gets the following authorization code" と表示)
3. トークンが `~/Mail/.mew-passwd.gpg` に保存され、inbox の取得が始まる

2 回目以降はブラウザ認可もパスワード入力も出ない (アクセス トークンの更新はリフレッシュ
トークンで自動)。

WSL では `browse-url` が `$BROWSER` (wsl-open) 経由で Windows 側ブラウザを開く。
`.wslconfig` が `networkingMode=mirrored` なので、Windows のブラウザからの
`localhost:28080` は WSL 側の Emacs に届く。

## 旧設定からの差分

| 旧 (`.mew.d/.mew.el`) | 今 | 理由 |
|---|---|---|
| `mew-prog-ssl "stunnel"`, `mew-ssl-verify-level 0` | `mew-ssl-default 'native` | Mew 6.10 から GnuTLS 直結。stunnel 不要 |
| `mew-search-method 'est` (Hyper Estraier) | 未設定 | `estcmd` が nixpkgs に無い。`mew-summary-pick` の grep 検索で代替。`mewest` もパッケージから外した |
| `mew-mailbox-type 'mbox` + `incm -d ~/Maildir` | 省略 | `~/Maildir` は無く、Gmail は IMAP。`incm` バイナリ自体は入れてある |
| `mew-use-master-passwd nil` + `mew-use-cached-passwd t` / `mew-passwd-lifetime 30` | `mew-use-master-passwd t` | 上記「なぜ master password 方式か」。キャッシュ寿命の設定は master 方式では使われない |
| `oauth2` (emacsmirror) + `plstore-*` / `epa-*` 設定 | 削除 | 2024-09 に試した `mew-support-xoauth2` フォーク + `oauth2.el` の名残。上流の XOAUTH2 は自前実装で不要 |
| `mm-version.el` (Mule コードネームの漢字化) | 省略 | Meadow 時代の装飾で実害なし |
| `Exchange` / `default` (example.net) ケース | Gmail の `default` 1 ケース | 実運用は Gmail のみ (`~/Mail/#imap` と `Smtplog` に Exchange の痕跡なし)。MS365 を足す場合は Entra ID のアプリ登録が要る (下記) |
| `smtp-ssl-port 587` | 465 | 旧環境の `Smtplog` で成功しているのは 465 (implicit TLS) のみ。587 は `Must issue a STARTTLS command first` で失敗していた |

`mew-use-suffix t` (メッセージファイルに `.mew` を付ける) は **変えてはいけない**。既存の
`~/Mail` は `1.mew` 形式で保存されており、nil にすると読めなくなる。

`mew-thread-indent-strings` は `mew-lang-jp.el` が日本語環境向けに `defvar` で罫線
`["┣" "┗" "┃" "　"]` に差し替えるが、[docs/eaw-width.md](eaw-width.md) の方針 (罫線は GUI / tty とも
幅 1、全角空白 U+3000 は幅 2) では幅が揃わず `mew-thread-setup` がエラーで止まる。旧 `.mew.el` と
同じ ASCII `[" +" " +" " |" "  "]` に固定してある。use-package の `:custom` では効かない
(`mew-lang-jp.el` の `defvar` が `mew-thread.el` の `defcustom` より先に束縛し、defcustom は既存の
現在値を優先する) ので `:init` の `setq` で読み込み前に束縛している。

## MS365 (Exchange Online) を足す場合

上流マニュアル (Sec 9.13) は Gmail と MS365 を通信確認済みとしている。ケース別キーで書ける:

```elisp
(Exchange
 (oauth2-auth-url     "https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize")
 (oauth2-token-url    "https://login.microsoftonline.com/organizations/oauth2/v2.0/token")
 (oauth2-resource-url "https://outlook.office.com/IMAP.AccessAsUser.All https://outlook.office.com/SMTP.Send offline_access")
 (imap-server "outlook.office365.com") (smtp-server "smtp.office365.com") ...)
```

前提は Entra ID のアプリ登録 (リダイレクト URI `http://localhost:28080` をモバイル/デスクトップ
プラットフォームで登録、パブリック クライアント フロー許可、API 権限 `IMAP.AccessAsUser.All` /
`SMTP.Send` / `offline_access`)。client-id / client-secret はケース別なので、1Password に別アイテムを
作り `my/mew-setup-oauth2` でケース別に入れる形に拡張する。

## 更新

```bash
# 上流の新しいコミットを決める
REV=$(gh api repos/kazu-yamamoto/Mew/commits/master --jq .sha)
# pkgs/mew.nix の rev / hash / version、elpaca.lock の mew :ref を同じ REV に揃える
nix flake prefetch --json github:kazu-yamamoto/Mew/$REV | jq -r .hash
nix build .#mew
```

Emacs 側は `M-x elpaca-checkout-branches` → `M-x elpaca-pull-all` → `M-x elpaca-write-lock-file`
(README「Emacs パッケージの更新 (elpaca)」) でも良いが、その場合も `pkgs/mew.nix` を同じ
コミットに合わせること。

## トラブルシュート

| 症状 | 見るところ |
|---|---|
| `op read … に失敗 (exit 1)` | 1Password (Windows 側 GUI) が起動・ロック解除されているか。`op read --no-newline "op://Personal/Mew Gmail XOAUTH2/password" \| wc -c` が 32 を返すか |
| `op read … の値が空です` | 1Password の `client-id` / `client-secret` が未入力 |
| `Master password is wrong!` | 旧 `.mew-passwd.gpg` が残っている (手順 3)。または 1Password の `password` を変えた |
| 認可後にブラウザが `localhost:28080` に繋がらない | Emacs 側でリスナが立っているか (`M-x list-processes` に `oauth2-redirect-handler:28080`)。WSL の `networkingMode` |
| `Must issue a STARTTLS command first` | `smtp-ssl-port` が 587 になっている。465 に戻す |
| `M-x mew` で `mewl` が無いと言われる | `home-manager switch` 後に Emacs を再起動したか (`exec-path` は起動時の PATH) |
| 1 時間ごとにブラウザ認可が出る | リフレッシュ トークンが無い。`(gethash :refresh_token (mew-passwd-get-passwd (car (mew-passwd-get-keys))))` が nil なら、認可 URL の override (`my/mew-oauth2-get-auth-code`) が効いているか確認し、`(mew-passwd-set-passwd k nil)` + `(mew-passwd-save)` で消してから再認可する |
| `All members of mew-thread-indent-strings must have the same length` | `mew-lang-jp.el` の罫線インデント `["┣" "┗" "┃" "　"]` が、この環境の文字幅 (罫線 1 / U+3000 2) で揃わない。init.el の `:init` で ASCII に固定してある。`:custom` に移すと効かない (defvar が先に束縛し defcustom は現在値を優先) |
