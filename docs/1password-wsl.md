# WSL での 1Password (Windows 版と Linux 版の併用)

WSL ホスト (wsl-nixos / wsl-gentoo) では、Windows 版と Linux 版 (WSLg 上の GUI) の 1Password を
両方起動し、用途ごとに使い分けている。npiperelay のような中継ツールは使わない。

経緯は Zenn の記事
[WSL2 で 1Password for Windows と 1Password for Linux を併用する](https://zenn.dev/nanasess/articles/1password-wsl2-windows-linux-setup)
にある。記事の後で設定が変わっているので、**現在の正本はこのドキュメント**とする
(記事との差分は末尾)。k-2 (NixOS) は Linux 版だけで完結するので、ここでは扱わない。

## 役割分担

| 用途 | 呼び出し元 (WSL 側) | 処理する 1Password | 認証 | 設定箇所 |
|---|---|---|---|---|
| ssh (WSL の Linux ssh、gcloud `--plain`、git over ssh) | `SSH_AUTH_SOCK` / `IdentityAgent` = `~/.1password/agent.sock` | **Linux 版**の SSH agent | Linux 版の承認 | `home.nix` (`home.sessionVariables`、`programs.ssh`) |
| git のコミット署名 | `gpg.ssh.program` = Windows の `op-ssh-sign.exe` | **Windows 版** | Windows Hello | `modules/wsl` (`programs.git.signing.signer`)。鍵と `format = ssh` は `home.nix` |
| `op` コマンド (`op read` / `op item ...` など) | `~/.local/bin/op` シム → Windows の `op.exe` | **Windows 版**の CLI 連携 | Windows Hello | `modules/wsl` (`home.file.".local/bin/op"`) |
| `op run` | シムが Linux 版の op (`wsl.opLinux`) に回す | **Linux 版**の CLI 連携 | Linux 版の承認 | `hosts/wsl-nixos/home.nix` / `hosts/wsl-gentoo.nix` の `wsl.opLinux` |
| シェル起動時の秘密情報 (`GITHUB_TOKEN` 等) | `$ZDOTDIR/.env.local` (名前付きパイプ) | **Linux 版**の 1Password Environments | 無し (起動中なら読める) | `modules/zsh` (`envExtra`) |
| gh / git の HTTPS 認証 | `gh auth git-credential` | (上の `GITHUB_TOKEN`) | — | `home.nix` (`credential."https://github.com".helper`) |
| Windows の ssh.exe (稀) | OpenSSH の既定の名前付きパイプ (`\\.\pipe\openssh-ssh-agent`) | **Windows 版**の SSH agent | Windows Hello | `modules/wsl` (`windowsSshConfig`、`docs/ssh-conf-d.md`) |

Windows 版の 1Password の SSH 履歴にコミット署名が並ぶのは、`op-ssh-sign.exe` が
Windows 側で署名しているためで、上の表のとおりの正しい動作。ssh 接続は Linux 版の履歴に出る。

## 前提となるアプリ側の設定 (手作業、リポジトリ管理外)

| 設定 | Windows 版 | Linux 版 |
|---|---|---|
| 開発者 → SSH エージェントを使用 | 有効 (コミット署名と Windows の ssh.exe 用) | 有効 (`~/.1password/agent.sock`) |
| 開発者 → 1Password CLI と連携 | 有効 (`op.exe`) | 有効 (`op run` 用) |
| Windows Hello | 有効 | — |
| `agent.toml` (agent が出す鍵の範囲) | `%LOCALAPPDATA%\1Password\config\ssh\agent.toml` | `~/.config/1Password/ssh/agent.toml` |

`agent.toml` は vault 名を含むので、このリポジトリ (public) には入れず手で置いている。
無いと Personal vault の鍵しか出てこない。

## 各部の詳細

### SSH agent (Linux 版)

- `home.sessionVariables.SSH_AUTH_SOCK` と `~/.ssh/config` の `Host *` の `IdentityAgent` が、
  どちらも `~/.1password/agent.sock` を指す。
- ソケットは Linux 版の 1Password が起動している間だけ存在する。
- `ssh-add` で鍵を追加することはできない (1Password の agent は読み取り専用)。
  1Password に登録できない古い鍵は `ssh-legacy` で一時的な agent を立てて使う
  (`modules/zsh`、`docs/ssh-conf-d.md`)。

### コミット署名 (Windows 版)

- `programs.git.signing`: `format = "ssh"`、`signByDefault = true`、`key` に公開鍵 (ed25519) を直接書く。
- WSL では `signer` を `/mnt/c/Users/<user>/AppData/Local/Microsoft/WindowsApps/op-ssh-sign.exe`
  (Microsoft Store / MSIX 版のパス) にしている。同じディレクトリには `op-ssh-sign-wsl.exe` もあり、
  1Password の「WSL 用の設定」スニペットはこちらを指す。今は `op-ssh-sign.exe` で署名でき、
  GitHub 上でも verified になっているので変えていない。
- 署名用の鍵は Windows 版と Linux 版の両方の agent から見える (同じアカウントの同じアイテム)。
  使われるのは `op-ssh-sign.exe` を経由する Windows 版だけ。
- **ローカルでは署名を検証できない**。`gpg.ssh.allowedSignersFile` を設定していないので、
  `git log --show-signature` や `%G?` は `N` / `E` を返す。署名されているかは
  `git cat-file -p <commit> | grep gpgsig` か、GitHub の Verified 表示で確かめる。

### `op` シム (`~/.local/bin/op`)

```text
op run ...  → wsl.opLinux (setgid onepassword-cli 付きの Linux 版 op) → Linux 版 1Password
op その他   → OP_* を WSLENV に載せて Windows の op.exe (WinGet) を exec → Windows 版 1Password
```

- `op run` を Linux 版に回すのは、Windows の `op.exe` が子プロセスに WSL の Linux コマンドを
  起動できないため。
- Linux 版の op は、Linux 版 1Password との通信に setgid `onepassword-cli` が必要になる。
  `/nix/store` のバイナリには setgid を付けられないので、ディストリが用意したものを使う。
  wsl-nixos は `programs._1password` の security wrapper (`/run/wrappers/bin/op`)、
  wsl-gentoo は portage (`/usr/bin/op`)。
- `OP_ACCOUNT` (`home.nix`) は、シムが WSLENV に載せるので `op.exe` にも届く。
- `op.exe` は WinGet で入れていて、Nix で管理していない。バージョンは Linux 版と揃っていない
  (2026-11 時点で `op.exe` 2.30.3、Linux 版 2.41.0)。上げるときは Windows 側で
  `winget upgrade AgileBits.1Password.CLI` を実行する。

### 1Password Environments (`.env.local`)

- `$ZDOTDIR/.env.local` (`~/.config/zsh/.env.local`) は名前付きパイプ (FIFO) で、
  平文はディスクに残らない。WSL のファイルシステムに FIFO を作れるのは Linux 版だけなので、
  Linux 版が提供していると判断している (アプリの画面では確認していない)。
- `modules/zsh` の `envExtra` が、**対話シェルに限って** 1 秒のタイムアウト付きで読む。
  Linux 版が起動していなければ警告を出して先に進む。
  非対話シェルで読まない理由は `modules/zsh` のコメントにある (.zshenv に出力が混ざって
  wslinfo を壊した実例)。
- `GITHUB_TOKEN` はここから供給していて、gh の Shell Plugins (`~/bin/gh`) は使っていない。

## トラブルシュート

| 症状 | 原因 | 対処 |
|---|---|---|
| `ssh` が `Permission denied (publickey)`、`ssh-add -l` が `Could not open a connection` / `Error connecting to agent` | Linux 版 1Password が起動していない (`~/.1password/agent.sock` が無い) | WSLg のスタートメニュー「1Password (NixOS)」から起動する |
| `git commit` が署名で失敗する (`error: ... failed to sign the data` 等) | Windows 版が起動していない、ロックされている、または Windows Hello を承認していない | Windows 版を起動・ロック解除して、もう一度コミットする |
| `op` が `[ERROR] ... authorization timeout` | `op.exe` の Windows Hello のダイアログに応答しなかった (Windows 側に出ていて気づかない) | Windows 側のダイアログに応答して再実行する |
| `op` が `account is not signed in` | `--account` を省き、`OP_ACCOUNT` も効いていない | 新しいシェルで実行する (`home.sessionVariables` は既存のシェルに反映されない) |
| Linux 版の op で `op whoami` だけが `account is not signed in` になる | `whoami` は CLI 連携の認証を始めないため。`op run` は同じ状態でも動く (2026-11 に確認) | 連携が有効かの判定には `whoami` を使わず、`op run` か `op read` で確かめる |
| `op run` で秘密情報が入らない / `op run` だけ失敗する | Linux 版の CLI 連携が無効、または Linux 版が起動していない | Linux 版の「1Password CLI と連携」を有効にする |
| シェル起動時に `[WARNING] Could not load secrets: 1Password is not running.` | Linux 版が起動していない (Environments の FIFO を読めない) | Linux 版を起動して新しいシェルを開く |
| wsl-gentoo で `op item create` が `invalid JSON in piped input` | `op.exe` が WSL から渡した標準入力のテンプレートを受け付けない | Linux 版の op (`wsl.opLinux`) で実行する |

## Zenn 記事との差分 (2026-11 時点)

| 項目 | 記事 | 現在 |
|---|---|---|
| `SSH_AUTH_SOCK` の設定 | `~/.zshrc` に export | `home.sessionVariables` |
| CLI 連携 | 追記後の方針は「Windows 版を有効、Linux 版を無効」 | **両方有効**。`op run` を Linux 版の op に回しているので、Linux 版の CLI 連携も要る (`op run` で秘密情報が取れることを確認済み) |
| Linux 版 op のパス | `/usr/bin/op` 固定 | ホストごとの `wsl.opLinux` (wsl-nixos は `/run/wrappers/bin/op`) |
| `op.exe` のパス | `<YOUR_USERNAME>` を置き換えて手書き | `config.home.username` から生成する (WinGet の Links) |
| 既定アカウント | 無し | `OP_ACCOUNT = "my.1password.com"` (シム経由で `op.exe` にも届く) |
| `~/.ssh/config` | 手書き | home-manager の `programs.ssh` + private の ssh_conf.d (`docs/ssh-conf-d.md`) |
| Windows の ssh.exe | 記載無し | `%USERPROFILE%\.ssh\config` を home-manager が生成し、Windows 版の agent を使う |
| 1Password に登録できない古い鍵 | 記載無し | Document に置き、`ssh-legacy` で一時的な agent に読み込む |
| gh の認証 | Shell Plugins から Environments の `GITHUB_TOKEN` へ移行する手順 | 移行済み (`gh auth status` が `GITHUB_TOKEN` を示す) |
