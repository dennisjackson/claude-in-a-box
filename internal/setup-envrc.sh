#!/usr/bin/env bash
# Set up .envrc with API keys for the dev container.
# Usage: ./setup-envrc.sh [-f]
#
# Prompts for each key interactively. Leave blank to skip.
# Skips keys that already have a value (in .envrc or environment) unless -f is given.

set -euo pipefail

ENVRC="$(dirname "$0")/../../.envrc"
FORCE=false
[[ "${1:-}" == "-f" ]] && FORCE=true

# Read existing values from .envrc (if it exists) into an associative array.
declare -A file_vals
if [[ -f "$ENVRC" ]]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^export\ ([A-Z_]+)= ]]; then
            file_vals["${BASH_REMATCH[1]}"]="$line"
        fi
    done < "$ENVRC"
fi

# Resolve current value: .envrc takes precedence, then environment.
current_value() {
    local key="$1"
    if [[ -n "${file_vals[$key]:-}" ]]; then
        # Extract the value from the export line
        eval "local v; ${file_vals[$key]}; v=\$$key"
        printf '%s' "$v"
    elif [[ -n "${!key:-}" ]]; then
        printf '%s' "${!key}"
    fi
}

KEYS=(ANTHROPIC_API_KEY)
declare -A new_vals

echo "Setting up $ENVRC"
echo "Press Enter to skip any key you don't have yet."
echo

for key in "${KEYS[@]}"; do
    cur="$(current_value "$key")"
    if [[ -n "$cur" ]] && ! $FORCE; then
        echo "$key: already set (use -f to overwrite)"
        new_vals["$key"]="$cur"
    else
        prompt="$key"
        [[ -n "$cur" ]] && prompt="$key [current: ${cur:0:4}...]"
        read -rp "$prompt: " input
        if [[ -n "$input" ]]; then
            new_vals["$key"]="$input"
        elif [[ -n "$cur" ]]; then
            new_vals["$key"]="$cur"
        fi
    fi
done

# Write .envrc — only include keys that have values.
: > "$ENVRC"
for key in "${KEYS[@]}"; do
    [[ -n "${new_vals[$key]:-}" ]] && echo "export $key=\"${new_vals[$key]}\"" >> "$ENVRC"
done

echo
echo "Written to $ENVRC"
echo "Run 'direnv allow' or 'source $ENVRC' to activate."
