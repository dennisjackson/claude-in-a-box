#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") [--done] BUG_NUM \"message\""
    echo
    echo "Add a timestamped entry to a bug's LOG.md."
    echo "  --done    Log the message, then move the bug folder to bugs/finished/"
    exit 1
}

DONE=false
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --done) DONE=true; shift ;;
        *) usage ;;
    esac
done

[[ $# -lt 2 ]] && usage

BUG_NUM="$1"
MESSAGE="$2"
BUGS_DIR="$(cd "$(dirname "$0")/.." && pwd)/bugs"

# Find the bug folder
BUG_DIR=$(ls -d "$BUGS_DIR"/*"$BUG_NUM"*/ 2>/dev/null | head -1)
if [[ -z "$BUG_DIR" ]]; then
    echo "Error: no bug folder found matching '$BUG_NUM' in $BUGS_DIR" >&2
    exit 1
fi

LOG_FILE="$BUG_DIR/LOG.md"
NOW=$(date -u +"%Y-%m-%d %H:%M UTC")

if [[ ! -f "$LOG_FILE" ]]; then
    echo "# Log: Bug $BUG_NUM" > "$LOG_FILE"
    echo >> "$LOG_FILE"
fi

echo "- $NOW — $MESSAGE" >> "$LOG_FILE"
echo "Logged to $LOG_FILE"

if $DONE; then
    FINISHED_DIR="$BUGS_DIR/finished"
    mkdir -p "$FINISHED_DIR"
    echo "- $NOW — Marked done, moved to finished/" >> "$LOG_FILE"
    mv "$BUG_DIR" "$FINISHED_DIR/"
    BASENAME=$(basename "$BUG_DIR")
    echo "Moved $BASENAME to bugs/finished/"
fi
