#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash) — 破壊的コマンドの決定論的ブロック
#
# モデルの判断 (CLAUDE.md) はプロンプトインジェクションで上書きされうるため、
# 最後の砦としてハーネス側で決定論的に遮断する。
#   - deny: システムパス・ホーム直下への rm 再帰+強制削除、mkfs、dd of=/dev/*
#   - ask : その他の rm 再帰+強制 (node_modules 削除等の正当用途があるため確認に留める)
# stdin: {"tool_name":"Bash","tool_input":{"command":"..."}}
set -u

# jq が無い環境では検査不能のため fail-closed にする。exit 2 が「ブロッキング
# エラー」(ツール実行を止める)。exit 1 等は非ブロッキングで実行が継続される。
if ! command -v jq >/dev/null 2>&1; then
  echo "block-dangerous-bash.sh: jq が見つからないため安全側でブロックします" >&2
  exit 2
fi

cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

emit() { # $1=permissionDecision $2=reason
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}

# ファイルシステム・デバイス破壊系は無条件 deny
if echo "$cmd" | grep -qE '(^|[;&|]\s*|\s)mkfs(\.[a-z0-9]+)?(\s|[;&|]|$)'; then
  emit deny "mkfs はブロック対象です (block-dangerous-bash.sh)"
fi
if echo "$cmd" | grep -qE "(^|[;&|]\s*|\s)dd\s[^;&|]*of=['\"]?/dev/"; then
  emit deny "dd による /dev/* への直接書き込みはブロック対象です (block-dangerous-bash.sh)"
fi

# rm の再帰フラグ + 強制フラグの併用を検出 (-rf / -fr / -r -f / --recursive --force / -Rf)
if echo "$cmd" | grep -qE '(^|[;&|]\s*|\s)rm\s' \
  && echo "$cmd" | grep -qE '\s(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)(\s|$)' \
  && echo "$cmd" | grep -qE '\s(-[a-zA-Z]*f[a-zA-Z]*|--force)(\s|$)'; then

  # rm と同一コマンドセグメント内 ([;&|] を跨がない) にシステムパス等の致命的
  # ターゲットがあれば deny。/home 直下・~ 直下は deny、それより深い個別パスは ask に落ちる。
  if echo "$cmd" | grep -qE "rm\s[^;&|]*\s['\"]?(/(bin|boot|dev|etc|lib|lib64|opt|proc|root|run|sbin|srv|sys|usr|var)(/[^[:space:];&|]*)?|/home(/[^/[:space:]]+)?/?|/\*?|~/?|\\\$HOME/?|\.\./?)([[:space:];&|'\"]|$)"; then
    emit deny "システムパス・ホーム直下への rm 再帰+強制削除はブロック対象です (block-dangerous-bash.sh)"
  fi
  emit ask "rm の再帰+強制削除が含まれます。対象パスを確認してください (block-dangerous-bash.sh)"
fi

exit 0
