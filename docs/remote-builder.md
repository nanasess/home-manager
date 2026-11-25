# k-2 のリモートビルダー (wsl-nixos)

k-2 (Intel 4 コア / 8 スレッド) の nix-daemon が、ビルドを ssh-ng で wsl-nixos
(AMD Zen 3、32 スレッド) に回す。主な目的は linux-t2 カーネルの自前ビルドで、
cache.soopy.moe に無い nixpkgs の rev でも k-2 で数時間かけずに済ませる
(2026-11-25 の実績: wsl-nixos で k-2 の toplevel 全体 514 derivation が 31 分 38 秒。
issue #252)。設定本体は `hosts/k-2/configuration.nix` と `hosts/wsl-nixos/configuration.nix`
の「リモートビルダー」セクション。

## 構成

```text
k-2 (nixos-rebuild / nix build)
  └─ nix-daemon (root)
       └─ ssh-ng: Host wsl-nixos-builder (/etc/ssh/ssh_config)
            HostName <Windows のコンピューター名>.local   ← mDNS (nss-mdns)
            Port 2222、鍵 /root/secrets/nix-builder_ed25519
                 │
                 ▼  Hyper-V ファイアウォール (Private プロファイルの LocalSubnet からの TCP 2222 だけ許可)
          Windows の LAN IP (WSL の mirrored モードなので wsl-nixos と共有)
                 │
                 ▼
          wsl-nixos の sshd :2222 (AllowUsers nix-ssh、パスワード認証なし)
            └─ nix-ssh ユーザー: ForceCommand nix-daemon --stdio (nix.sshServe)
```

- **接続先の名前**: Windows の IP は DHCP で変わるので、Windows が mDNS で応答する
  コンピューター名 (`<名前>.local`) で引く。k-2 の avahi-daemon は GNOME が入れているが、
  glibc (ssh) から `.local` を引くには `services.avahi.nssmdns4 = true` が要る
  (無い状態では `avahi-resolve -4 -n <名前>.local` は引けても `getent ahostsv4` は失敗した)。
  Windows のコンピューター名を変えたら `programs.ssh.extraConfig` の `HostName` を更新する。
- **ホスト鍵**: `HostKeyAlias wsl-nixos-builder` で別名に結び付け、`programs.ssh.knownHosts`
  に固定する。名前や IP が変わっても knownHosts は書き換えなくてよい。
  wsl-nixos を作り直してホスト鍵が変わったら更新する。
- **どのビルドが回るか**: wsl-nixos に繋がる間は、`preferLocalBuild` の付いた小さな
  derivation 以外はほぼ wsl-nixos に回る。cache.nixos.org にある入力は
  `builders-use-substitutes = true` で wsl-nixos が自分で取る。
- **wsl-nixos が止まっているとき**: Windows のスリープ中、`wsl --shutdown` の後、外出先では
  繋がらない (外からの SSH 接続では WSL は起動しない)。`ConnectTimeout 5` で諦めて
  k-2 でビルドする。

## 鍵 (k-2 の root)

ビルドの接続は nix-daemon (root) が行うので、ユーザーの 1Password SSH agent は使えない。
restic の鍵 ([restic-nas.md](restic-nas.md)) と同じく、パスフレーズなしの専用鍵を
`/root/secrets/` に置き、正本は 1Password に控える (CLAUDE.md「1Password とクレデンシャル管理」
の例外運用)。鍵で入れるのは wsl-nixos の `nix-ssh` だけで、ForceCommand により
nix-daemon 以外は動かせない。

```bash
# k-2 上
sudo install -d -m 700 /root/secrets
sudo ssh-keygen -t ed25519 -N '' -C 'k-2 nix-daemon -> wsl-nixos builder' \
  -f /root/secrets/nix-builder_ed25519
sudo cat /root/secrets/nix-builder_ed25519.pub   # → wsl-nixos の nix.sshServe.keys
```

秘密鍵は 1Password に SSH Key アイテムとして保存する。復旧時は `op read` で取り出して
`/root/secrets/nix-builder_ed25519` (0600) に置く。

`nix.sshServe.trusted = true` (nix-ssh を trusted-users に入れる) は、k-2 から署名の無い
入力パスを受け取るのに要る。つまり k-2 の root は wsl-nixos のストアに任意のパスを
入れられる。自分の 2 台の間で、鍵認証かつ LAN 限定なので許容している。

## Windows 側 (Hyper-V ファイアウォール)

mirrored モードでは WSL への受信は Hyper-V ファイアウォールが決め、既定は Block
(`Get-NetFirewallHyperVVMSetting -PolicyStore ActiveStore -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'`
の `DefaultInboundAction`)。管理者の PowerShell でルールを足す:

```powershell
New-NetFirewallHyperVRule -Name nix-builder -DisplayName "nix builder (WSL sshd 2222)" `
  -Direction Inbound -VMCreatorId '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' `
  -Protocol TCP -LocalPorts 2222 -RemoteAddresses LocalSubnet -Profiles Private
# 確認 / 削除
Get-NetFirewallHyperVRule -Name nix-builder
Remove-NetFirewallHyperVRule -Name nix-builder
```

mDNS の応答には Windows Defender ファイアウォールの「mDNS (UDP 受信)」ルールが要る
(既定で有効。LAN が Private プロファイルであることも確認する)。

`-Profiles` を省略すると `Any` になり、Public のインターフェース (外出先の Wi-Fi 等) にも
適用されて、そのネットワーク内から 2222 番に届く。鍵認証の nix-ssh しか入れないが、
自宅 LAN (Private) に絞っておく。作成済みのルールは
`Set-NetFirewallHyperVRule -Name nix-builder -Profiles Private` で変えられる
(`Get-NetFirewallHyperVRule -Name nix-builder` の `Profiles` と、`PortStatuses` に
Private のポートだけが並ぶことで確認する)。

## 確認

```bash
# k-2 上
getent ahostsv4 <Windows のコンピューター名>.local        # nss-mdns で引けること
# 接続と nix-daemon の応答 (Trusted: 1 なら OK)。/etc/ssh/ssh_config の Host には User / IdentityFile が
# 無いので、ユーザーと鍵は URL で渡す (省くと root@… で接続して Permission denied になる)。
# nix-daemon は /etc/nix/machines の sshUser / sshKey を使うので、ビルドにはこの指定は要らない
sudo nix store info --store 'ssh-ng://nix-ssh@wsl-nixos-builder?ssh-key=/root/secrets/nix-builder_ed25519'
# 毎回中身が変わる derivation を、ローカルでは作らせずにビルドする → 32 なら wsl-nixos で動いた
nix build --no-link --print-out-paths --max-jobs 0 --impure --expr \
  "(builtins.getFlake \"nixpkgs\").legacyPackages.x86_64-linux.runCommand \"rb-test-$(date +%s)\" {} \"nproc > \$out\"" \
  | xargs cat
```

`nix-ssh` で普通にログインしようとしても (`sudo ssh -i /root/secrets/nix-builder_ed25519 nix-ssh@wsl-nixos-builder`)
シェルには入れず、nix-daemon のプロトコル待ちになる。

## 切り分け

| 症状 | 原因の候補 |
|---|---|
| `Could not resolve hostname …local` | k-2 の nss-mdns が無い / Windows の mDNS ルール / Windows のコンピューター名変更 |
| `Connection timed out` | WSL が止まっている / Hyper-V ルールが無い / wsl-nixos の sshd が止まっている (`systemctl status sshd`) |
| `Host key verification failed` | wsl-nixos を作り直してホスト鍵が変わった (`/etc/ssh/ssh_host_ed25519_key.pub` を knownHosts に) |
| `Permission denied (publickey)` | 手動の確認で URL に `nix-ssh@` / `?ssh-key=` が無い (`root@…` で接続している) / `/root/secrets/nix-builder_ed25519` が無い・権限が広い / `nix.sshServe.keys` と食い違い |
| 回らずに k-2 でビルドされる | `nix show-config | grep builders` / `supportedFeatures` に要求 feature (`big-parallel` 等) が無い |
