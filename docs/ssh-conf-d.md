# ホスト別 ssh 設定 (`~/.ssh/conf.d`)

## 構成

| 層 | 場所 | 管理 |
|---|---|---|
| 共通設定 (`Host *` の `IdentityAgent` / `SetEnv TERM`) と `Include` | `~/.ssh/config` | このリポジトリ (`home.nix` の `programs.ssh`) |
| ホスト別設定 (`Host` / `HostName` / `User` / `Port` 等) | `~/.ssh/conf.d/*.conf` | **private** リポジトリ `nanasess/ssh_conf.d` の clone |
| 鍵 | 1Password の SSH Key アイテム (agent) | 1Password |
| 1Password に SSH Key として登録できない古い鍵 | 1Password の Document / Secure Note の添付 | 1Password。使うときだけ一時 agent に読み込む (`ssh-legacy` 関数、`modules/zsh`) |

ホスト別設定は顧客名と接続先の一覧なので、このリポジトリ (public) には入れない。
submodule や flake input にもしない (flake input にすると `flake.lock` に private リポジトリが載り、
CI と第三者の clone が取得に失敗する)。

`~/.ssh/config` の `Include` は `Host *` より前にあるので、conf.d の値が優先される
(ssh_config は最初に得た値を採用する)。conf.d が無くても `Include` はエラーにならず黙って
無視されるため、activation (`home.nix` の `sshConfDCheck`) が clone 漏れを警告する。

## セットアップ (ホストごとに 1 回)

```bash
git clone git@github.com:nanasess/ssh_conf.d.git ~/.ssh/conf.d
```

更新は `git -C ~/.ssh/conf.d pull`。

## ssh で問題が起きたときの切り分け (Claude 向け手順)

ユーザーから「ssh で `<host>` に繋がらない」と相談されたら、推測で直さず次の順で切り分ける。

1. **どの設定が効いているかを特定する**
   ```bash
   ssh -G <host> | grep -E '^(hostname|user|port|identityagent|identityfile|identitiesonly|hostkeyalgorithms|pubkeyacceptedalgorithms) '
   timeout 20 ssh -v -o BatchMode=yes -o ConnectTimeout=10 <host> true 2>&1 \
     | grep -E 'Applying options|Connecting to|connect to|Offering|Authenticated|Permission denied|no matching|Could not resolve|IDENTIFICATION HAS CHANGED'
   ```
   `debug1: /home/nanasess/.ssh/conf.d/<file>.conf line N: Applying options for <host>` に、
   適用されたファイルと行が出る。conf.d の行が出ていなければ、該当する `Host` が無い
   (別名の綴り違い、または conf.d 未 clone)。
   **ログインまで試す (`ssh ... true`) のは接続先に記録が残る操作なので、ユーザーが対象ホストを
   指定して相談してきたときに限る。**

2. **症状で原因を分ける**

   | 症状 | 主な原因 | 直す場所 |
   |---|---|---|
   | `Could not resolve hostname <別名>` | conf.d に `Host` が無い / 綴り違い / conf.d 未 clone | conf.d |
   | `Connection timed out` / `Connection refused` | サーバー廃止、IP 変更、ポート変更、接続元 IP の制限 | conf.d (`HostName` / `Port`)。廃止なら棚卸しへ |
   | `Permission denied (publickey)` | `User` 違い、鍵が 1Password に無い、古い鍵が必要 | conf.d (`User` / `IdentityFile`)。古い鍵は `ssh-legacy` か 1Password の添付から一時 agent へ |
   | `Too many authentication failures` | 1Password agent が鍵を順に出して上限に当たる | conf.d に `IdentityFile ~/.ssh/<鍵>.pub` + `IdentitiesOnly yes` (公開鍵は 1Password からエクスポートして置く) |
   | `no matching host key type found` / `no mutual signature algorithm` | 古いサーバーが `ssh-rsa` (SHA-1) しか話さない | conf.d の該当 `Host` に `HostKeyAlgorithms +ssh-rsa` / `PubkeyAcceptedAlgorithms +ssh-rsa` (先頭の `+` で既定に追加する) |
   | `REMOTE HOST IDENTIFICATION HAS CHANGED` | サーバー再構築、または中間者 | conf.d ではない。正当な変更かをユーザーに確認してから `ssh-keygen -R <host>` |

3. **conf.d を直して PR にする** — `~/.ssh/conf.d` は private リポジトリの作業ツリーそのもの。
   ```bash
   git -C ~/.ssh/conf.d switch -c fix/<内容>
   # 編集して、上の 1. のコマンドで直ったことを確認する
   git -C ~/.ssh/conf.d add <file>.conf
   git -C ~/.ssh/conf.d commit -m 'fix: ...'
   git -C ~/.ssh/conf.d push -u origin HEAD
   gh pr create -R nanasess/ssh_conf.d --base main ...
   ```
   作業ツリーがそのまま実環境なので、マージ後は `git -C ~/.ssh/conf.d switch main && git -C ~/.ssh/conf.d pull`
   で戻す。ssh_conf.d は private なので PR に顧客名や IP を書いてよいが、**このリポジトリ
   (home-manager) の Issue / PR / コミットには書かない**。

## 棚卸し

年に 1 回程度、または切り分けで「サーバー廃止」が疑われたときに行う。

1. **到達性を一覧にする** (ログインはしない。`ssh-keyscan` は sshd のバナーと鍵を受け取るだけ):
   ```bash
   for f in ~/.ssh/conf.d/*.conf; do
     awk 'tolower($1)=="host"{for(i=2;i<=NF;i++) if ($i !~ /[*?!]/) print $i}' "$f" | while read -r h; do
       read -r hn port < <(ssh -G "$h" </dev/null 2>/dev/null | awk '$1=="hostname"{h=$2} $1=="port"{p=$2} END{print h, p}')
       if ! getent ahosts "$hn" >/dev/null; then st=dns-fail
       elif ssh-keyscan -T 5 -p "$port" "$hn" </dev/null 2>/dev/null | grep -q .; then st=ok
       else st=unreachable; fi
       printf '%-12s %-28s %-36s %s\n' "$st" "$(basename "$f")" "$h" "$hn:$port"
     done
   done
   ```
2. **結果をユーザーに見せて判断を仰ぐ**。`unreachable` でも接続元 IP の制限 (VPN 経由のみ等) で
   正常なことがあるので、Claude だけで削除を決めない。
3. **廃止と確定したホスト**は、ファイルから削除するか `zz-obsolete.conf` に移す。対応する鍵が
   1Password にあれば、そのアイテム (または添付) も削除候補としてユーザーに伝える。
4. ssh_conf.d に PR を出す (上の手順 3)。
