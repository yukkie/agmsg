#!/usr/bin/env bash
set -euo pipefail

# Usage: history.sh <team> [agent_id] [limit]
# Shows message history. If agent_id given, shows only that agent's messages.

TEAM="${1:?Usage: history.sh <team> [agent_id] [limit]}"
AGENT="${2:-}"
LIMIT="${3:-20}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/storage.sh"
DB="$(agmsg_db_path)"

if [ ! -f "$DB" ]; then
  echo "No messages (DB not initialized)"
  exit 0
fi

if [ -n "$AGENT" ]; then
  WHERE="WHERE team='$TEAM' AND (from_agent='$AGENT' OR to_agent='$AGENT')"
else
  WHERE="WHERE team='$TEAM'"
fi

# Escape newlines/tabs in body, use unit separator between fields. Select
# discrete columns with -separator so 0x1F is emitted as a real byte — the
# Windows sqlite3.exe CLI renders an embedded char(31) as the literal "^_",
# which breaks the IFS split below (see watch.sh for the same pattern).
RESULT=$(sqlite3 -separator $'\x1f' "$DB" "
  SELECT from_agent, to_agent, replace(replace(body, char(10), '\n'), char(9), '\t'), created_at, CASE WHEN read_at IS NULL THEN '●' ELSE '○' END
  FROM messages $WHERE ORDER BY created_at DESC LIMIT $LIMIT;
")

if [ -z "$RESULT" ]; then
  echo "No message history."
  exit 0
fi

# Reverse order (oldest first) and display
REVERSED=$(echo "$RESULT" | tail -r 2>/dev/null || echo "$RESULT" | tac 2>/dev/null || echo "$RESULT" | awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}')
while IFS=$'\x1f' read -r from to body ts status; do
  status="${status%$'\r'}"  # strip trailing CR from Windows sqlite3.exe CRLF line endings
  echo "  $status [$ts] $from → $to: $body"
done <<< "$REVERSED"
