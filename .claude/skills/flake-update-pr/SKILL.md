---
name: flake-update-pr
description: nix flake update の結果を PR 化する。closure 差分から更新パッケージ一覧を生成し PR 本文に記載する。Use when running or reviewing a flake.lock update in this repository.
---

# flake update の PR 作成

`nix flake update` による `flake.lock` の更新を PR にするまでの手順。
**更新パッケージ一覧を PR 本文に記載することが必須**。lock の revision だけでは何が変わったか分からないため。

## 1. 更新内容の確認

```bash
git diff flake.lock
```

どの input が更新されたかを控える (input 名 / 旧 rev / 新 rev)。
`inputs.nixpkgs.follows` している input は lock に独自の変更が出ないため、PR 本文でその旨に触れる。

## 2. ブランチ作成

`main` にいる場合は必ずブランチを切る。

```bash
git checkout -b chore/flake-update-<YYYYMMDD>
```

## 3. ビルド検証

CI 任せにせず、ローカルで実行できるものは実行する。

```bash
nix flake check
nix build '.#homeConfigurations."nanasess@wsl-gentoo".activationPackage' --no-link --print-out-paths
nix build '.#homeConfigurations."nanasess@ubuntu".activationPackage' --no-link
```

- 時間がかかるのでバックグラウンド実行を推奨。
- `nanasess@macbook` は Linux ホストではビルド不可。**ローカル未検証と明示**し、CI (macos-15-intel) の結果に委ねる。
- `nix flake check` は `aarch64-darwin` / `x86_64-darwin` を非対応システムとしてスキップする。これは失敗ではない。

## 4. コミット

Conventional Commits + 日本語。本文に input の rev 変化を書く。

```
chore(deps): nix flake update (nixpkgs, home-manager)

- nixpkgs: <old> -> <new> (nixos-unstable)
- home-manager: <old> -> <new> (master)
```

## 5. 更新パッケージ一覧の生成 [必須]

新旧両方の `activationPackage` をビルドして `nix store diff-closures` で比較する。
比較対象は代表ホストとして `nanasess@wsl-gentoo` を使う。

```bash
# 旧 lock 側は main の worktree を一時的に作って評価する
git worktree add /tmp/hm-old main
OLD=$(nix build --no-link --print-out-paths \
  '/tmp/hm-old#homeConfigurations."nanasess@wsl-gentoo".activationPackage')
NEW=$(nix build --no-link --print-out-paths \
  '.#homeConfigurations."nanasess@wsl-gentoo".activationPackage')

# closure サイズの比較
nix path-info -Sh "$OLD" "$NEW"

# パッケージ差分 (ANSI 除去してファイルへ)
nix store diff-closures "$OLD" "$NEW" | sed -e 's/\x1b\[[0-9;]*m//g' > /tmp/diff-closures.txt

git worktree remove /tmp/hm-old
```

**落とし穴**: `nix store diff-closures ... | head -N` は SIGPIPE で出力が途中で切れる。
必ず全量をファイルへ書き出してから絞り込むこと。

### 宣言パッケージとの突き合わせ

差分は数百件になるため、`home.packages` で宣言しているパッケージを抜き出して表にする。

```bash
nix eval --raw '.#homeConfigurations."nanasess@wsl-gentoo".config.home.packages' \
  --apply 'ps: builtins.concatStringsSep "\n" (map (p: p.name or "?") ps)' \
  | sed -E 's/-(unstable.*|[0-9].*)$//' | sort -u > /tmp/declared-names.txt

grep ' → ' /tmp/diff-closures.txt | grep -v '^python3' > /tmp/vchanges.txt
while read -r n; do grep -E "^${n}: " /tmp/vchanges.txt; done < /tmp/declared-names.txt | sort -u
```

### closure が大きく増えた場合

原因パッケージの参照経路を必ず特定して PR 本文に書く。

```bash
P=$(nix path-info -r "$NEW" | grep -E '<pkg>-<version>$' | head -1)
nix why-depends "$NEW" "$P"
```

上流由来かこのリポジトリの変更由来かを切り分け、対処するかどうかの判断材料を残す。

## 6. PR 本文

このリポジトリに PR テンプレートは無い。以下の構成で書く。

```markdown
## Summary
<input の rev 変化を表で>

## Changes
<変更ファイル>

## Test plan
<実行したコマンドと結果のチェックリスト。未検証項目は理由付きで未チェックのまま残す>

---

## 更新パッケージ一覧 (closure 差分)

<計測方法: 比較した store path と closure サイズ>

### 内訳
<バージョン変更 / 追加 / 削除 / サイズのみ の件数表>

### 宣言パッケージ (`home.packages`) のバージョン変更
<before / after の表>

### 注意点
<closure サイズの増減とその原因、why-depends の結果など>

<details>
<summary>closure 差分 全 N 件 (nix store diff-closures)</summary>

（全量をコードブロックで）

</details>
```

- **一覧は PR コメントではなく PR 本文に書く。** 後から履歴を追う際に本文だけで完結させるため。
- 全量リストは `<details>` で折りたたむ。GitHub の本文上限は 65536 文字なので、超える場合は `<details>` 内を「非 python の変更のみ」等に絞り、絞った旨を明記する。
- `python3.13-*` → `python3.14-*` のような系統移行は追加/削除の件数を押し上げる。まとめて 1 行で説明する。

## 7. PR 作成

```bash
gh pr create --base main --title "chore(deps): nix flake update (<inputs>)" --body-file <body.md>
```

本文が長いので `--body-file` を使う。作成後に本文を差し替える場合は `gh pr edit <n> --body-file <body.md>`。

**注意**: `gh` を scratchpad 等の git 管理外ディレクトリから実行するとリポジトリ解決に失敗する。
リポジトリルートで実行するか `--repo nanasess/home-manager` を付ける。
