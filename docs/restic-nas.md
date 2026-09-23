# restic による k-2 のバックアップ (Synology DS720+ "home-backup")

k-2 (NixOS) の flake で再現できない状態を、restic で Synology NAS (DS720+, DSM 7.4.1) に
毎時送る。設定本体は `hosts/k-2/configuration.nix` の「バックアップ」セクション。
ここには NAS 側の準備、実機で踏んだ落とし穴、復旧手順をまとめる (2026-09-22 時点)。

## 方針

- **取るもの**: `/home/nanasess` (キャッシュ類を除外)、`/etc/NetworkManager/system-connections`
  (VPN の秘密)、`/var/lib/bluetooth` (ペアリング鍵)
- **取らないもの**: `/nix`、NixOS / home-manager が生成する設定、`~/.cache` 等の再生成可能な
  もの、OneDrive (クラウドが正)、`node_modules` / `vendor` 等の依存 (除外一覧は configuration.nix)
- **復旧経路**: [nixos-t2.md](nixos-t2.md) の手順で再インストール →
  `nixos-rebuild switch --flake .#k-2` → `restic-nas restore`。ディスクイメージは取らない
- **ツール選定**: restic は NAS 側が DSM 組み込みの SFTP だけで済む (borg はサーバ側に
  borg バイナリが要る)。Active Backup for Business の Linux エージェントは deb/rpm 前提で
  NixOS では使えない

## NAS 側の設定

1. **共有フォルダ `restic`** (Btrfs ボリューム)。ごみ箱は**無効** (restic の prune が消した
   pack がごみ箱に残って容量を食う)。データチェックサムも不要 (restic が全ブロックを自前で
   検証する)。暗号化も不要 (restic 側で暗号化済み)
2. **ユーザー `backup`**: `restic` のみ read/write、他の共有フォルダは「アクセスなし」、
   アプリケーション権限は SFTP のみ、administrators には入れない。
   k-2 側の秘密鍵はパスフレーズなしでディスクに置くため、`nanasess` の鍵を流用すると
   k-2 侵害時に TimeMachine 等の他フォルダまで消せてしまう
3. **ファイルサービス → FTP → SFTP を有効化**。「端末と SNMP」の SSH は不要
   (非 admin は SSH ログインできない仕様。SFTP サービスは別枠で動く)
4. **ユーザーホームサービスを有効化** (`authorized_keys` の置き場所)
5. **Snapshot Replication** で `restic` フォルダに日次スナップショット。保持 14 日、
   **変更不可スナップショット**を有効 (保護期間 7 日程度)。k-2 の鍵が漏れても NAS 上の
   履歴は消せなくなる。「スナップショットを表示」は無効にする

### DSM の SFTP は仮想ルート

非 admin ユーザーが SFTP でログインすると、実ファイルシステムではなく「権限のある共有フォルダを
`/` 直下に並べた仮想ルート」が見える:

```
sftp> pwd
Remote working directory: /
sftp> ls -al
drwxrwxrwx    1 backup   users           0 Sep 22 09:45 home     ← /volume1/homes/backup
drwxrwxrwx    1 root     root           54 Sep 22 09:45 homes
drwxrwxrwx    1 root     root           12 Sep 22 09:25 restic   ← /volume1/restic
```

したがって restic のリポジトリは `sftp:backup@192.168.100.15:/restic/k-2` であって
`/volume1/restic/k-2` ではない。`ls` が返すパーミッションは常に 777 に見えるが ACL 管理の
見せかけで、`chmod` の実効は sshd が鍵を受け入れるかどうかで判断する。

### authorized_keys の配置 (NAS に SSH で入らずに済む)

k-2 で `/root/secrets/restic-nas_ed25519` を作った後、`backup` のパスワードで SFTP 接続して
自分で置く:

```
sudo cat /root/secrets/restic-nas_ed25519.pub > /tmp/authorized_keys
sftp backup@192.168.100.15
sftp> cd home
sftp> mkdir .ssh
sftp> chmod 700 .ssh
sftp> put /tmp/authorized_keys .ssh/authorized_keys
sftp> chmod 600 .ssh/authorized_keys
sftp> bye
rm /tmp/authorized_keys
```

鍵認証が通らないときは admin で SSH を一時的に有効にして実体側を直す
(`/volume1/homes/backup` を 755、`.ssh` を 700、`authorized_keys` を 600、`chown -R backup:users`。
それでもだめなら `synoacltool -get` で ACL を確認)。今回は SFTP 経由の `chmod` だけで通った。

## k-2 側の秘密情報

`/root/secrets/` (0700) は Nix 管理外で手動配置。systemd から動くため 1Password の SSH agent は
使えず、この 2 ファイルだけは復号値をディスクに置く (CLAUDE.md の例外運用)。

| ファイル | 内容 | 作り方 |
|---|---|---|
| `restic-nas.pass` (0600) | リポジトリのパスフレーズ | `umask 077; head -c 32 /dev/urandom \| base64 > /root/secrets/restic-nas.pass` |
| `restic-nas_ed25519` (0600) | `backup` ユーザー用 SSH 秘密鍵 (パスフレーズなし) | `ssh-keygen -t ed25519 -N '' -f /root/secrets/restic-nas_ed25519` |

正本は 1Password の `synology` vault、`restic-key` アイテムに控える。**パスフレーズを失うとリポジトリは
二度と開けない**。NAS のホスト鍵は `programs.ssh.knownHosts` で `/etc/ssh/ssh_known_hosts`
に載せている (root の `~/.ssh/known_hosts` には無いので、これが無いと `BatchMode=yes` で
`Host key verification failed` になる)。NAS を再インストールしたら更新する。

## 運用

```bash
systemctl status restic-backups-nas.timer      # 次回実行
systemctl start restic-backups-nas.service     # 手動実行 (初回はこれで initialize させる)
journalctl -u restic-backups-nas -n 50
sudo restic-nas snapshots                      # NixOS が生やす wrapper (repo / password 設定済み)
sudo restic-nas stats latest
```

- 外出先など NAS に届かないときは `ConnectTimeout=10` で失敗して終わり、次回に持ち越す
  (`Persistent=true` で起動時に追いつく)。失敗ログ自体は正常
- 実行中にサスペンドしても構わない (suspend は止めない。理由は後述「落とし穴」)
- DSM の OpenSSH 8.2 が post-quantum 鍵交換に非対応で ssh が警告を出す。LAN 内なので無視
- 半年に一度: `sudo restic-nas check --read-data-subset=10%` と試験リストア

## 復旧

```bash
# 特定パスだけ戻す
sudo restic-nas restore latest --target /tmp/restore --include /home/nanasess/Mail
# ホーム全体 (再インストール直後。home-manager の activation 前に戻すと衝突しない)
sudo restic-nas restore latest --target / --include /home/nanasess
# ホーム以外 (VPN の接続プロファイルと Bluetooth のペアリング鍵)
sudo restic-nas restore latest --target / --include /etc/NetworkManager/system-connections
sudo restic-nas restore latest --target / --include /var/lib/bluetooth
```

再インストール直後は `/root/secrets/` が無いので、1Password から復元してから `nixos-rebuild switch`
(`restic-nas` wrapper が入れば上記が使える):

```bash
sudo install -d -m 700 /root/secrets
op read 'op://synology/restic-key/restic-nas.pass' | sudo install -m 600 /dev/stdin /root/secrets/restic-nas.pass
op read 'op://synology/restic-key/private_key'     | sudo install -m 600 /dev/stdin /root/secrets/restic-nas_ed25519
```

## 落とし穴: サスペンド復帰直後の追いつき実行

`services.restic.backups.<name>.inhibitsSleep = true` にすると、サスペンドからの復帰直後に
`Persistent = true` の追いつき実行が走ったとき、logind がまだ `suspend` 操作を終えておらず
`systemd-inhibit` が拒否されてその回が失敗する:

```
20:34:46 systemd-sleep: System returned from sleep operation 'suspend'.
20:34:46 systemd-logind: Operation 'suspend' finished.
20:34:46 systemd-inhibit: Failed to inhibit: The operation inhibition has been requested for is already running
20:34:46 systemd: restic-backups-nas.service: Failed with result 'exit-code'.
```

ノート PC では復帰のたびに再現するので無効にしてある (2026-09-22、k-2 実機)。差分バックアップは
十数秒で終わり、restic は中断されても壊れない (次回の `unlock` でロックが外れる)。

`inhibitsSleep` を外した後も、同じ「復帰直後」の競合が別の症状で残っていた。WiFi が上がる前に
追いつき実行が走ると NAS に届かない:

```
2026-09-22 20:40:25 kernel: PM: suspend entry (deep)
2026-09-23 14:04:54 systemd: Starting restic-backups-nas.service...
2026-09-23 14:04:54 restic-backups-nas-pre-start: ssh: connect to host 192.168.100.15 port 22: Network is unreachable
2026-09-23 14:04:55 kernel: PM: suspend exit
```

unit の `After=network-online.target` は起動時に到達済みで、復帰時には何も待たない。
`backupPrepareCommand` で NAS が ping に応答するまで最大 3 分待ってから本体に進むようにした
(届かなければそのまま進んで restic が通常どおり失敗し、次回に持ち越す。外出先の挙動は変わらない)。
`Type=oneshot` の `TimeoutStartSec` は無限なので、3 分待っても systemd に打ち切られない
(初回の全量 2 分 24 秒が通っていることでも確認できる)。
