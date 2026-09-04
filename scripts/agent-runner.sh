#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT="$ROOT/.agent"
QUEUE="$AGENT/queue"
LOGS="$AGENT/logs"
mkdir -p "$QUEUE" "$LOGS"

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.cargo/bin:/usr/local/bin:$PATH"

printf '\n  Forge Browser build runner\n'
printf '  root : %s\n' "$ROOT"
printf '  watch: %s\n' "$QUEUE"
printf '  Every command is printed here before it runs. Ctrl-C to stop.\n\n'

while true; do
  job="$(ls -1 "$QUEUE"/*.sh 2>/dev/null | head -n1 || true)"
  if [ -n "${job:-}" ]; then
    id="$(basename "$job" .sh)"
    printf '\033[1;36m==> job %s\033[0m\n' "$id"
    sed 's/^/    /' "$job"
    printf '\n'
    ( cd "$ROOT" && bash "$job" ) > "$LOGS/$id.log" 2>&1
    code=$?
    printf '\nEXIT=%s\n' "$code" >> "$LOGS/$id.log"
    tail -n 15 "$LOGS/$id.log" | sed 's/^/    /'
    rm -f "$job"
    printf '%s' "$code" > "$LOGS/$id.done"
    printf '\033[1;32m<== job %s finished (exit %s)\033[0m\n\n' "$id" "$code"
  fi
  sleep 1
done
