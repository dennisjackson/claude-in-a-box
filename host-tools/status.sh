#!/bin/bash
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Helper: run a command in the container as the vscode user
cexec() { docker exec -u vscode "$CONTAINER_ID" "$@"; }

# --- Colours & helpers -------------------------------------------------------
bold=$'\033[1m'
dim=$'\033[2m'
green=$'\033[32m'
yellow=$'\033[33m'
red=$'\033[31m'
cyan=$'\033[36m'
reset=$'\033[0m'

section() { printf '\n%s=== %s ===%s\n' "$bold$cyan" "$1" "$reset"; }
kv()      { printf '  %-24s %s\n' "$1" "$2"; }
warn()    { printf '  %s⚠  %s%s\n' "$yellow" "$1" "$reset"; }
ok()      { printf '  %s✓  %s%s\n' "$green" "$1" "$reset"; }
err()     { printf '  %s✗  %s%s\n' "$red" "$1" "$reset"; }

# --- Container status --------------------------------------------------------
section "Container"

CONTAINER_ID=$(docker ps -q --filter "label=devcontainer.local_folder=$PROJ_DIR" 2>/dev/null || true)

if [ -z "$CONTAINER_ID" ]; then
    # Check for stopped container
    STOPPED_ID=$(docker ps -aq --filter "label=devcontainer.local_folder=$PROJ_DIR" 2>/dev/null || true)
    if [ -n "$STOPPED_ID" ]; then
        err "Container exists but is stopped (${STOPPED_ID:0:12})"
        CREATED=$(docker inspect -f '{{.Created}}' "$STOPPED_ID" 2>/dev/null || echo "unknown")
        kv "Created:" "$CREATED"
    else
        err "No container found"
    fi
    # Still report on volumes and bind mounts below
    CONTAINER_ID=""
else
    ok "Running (${CONTAINER_ID:0:12})"
    CREATED=$(docker inspect -f '{{.Created}}' "$CONTAINER_ID" 2>/dev/null || echo "unknown")
    UPTIME=$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER_ID" 2>/dev/null || echo "unknown")
    IMAGE=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER_ID" 2>/dev/null || echo "unknown")
    kv "Created:" "$CREATED"
    kv "Started:" "$UPTIME"
    kv "Image:" "$IMAGE"
fi

# --- Named volumes (survive rebuilds) ----------------------------------------
section "Persistent Volumes"

for vol in nss-dev-nss nss-dev-nspr nss-dev-ccache; do
    info=$(docker volume inspect "$vol" --format '{{.CreatedAt}}' 2>/dev/null || true)
    if [ -n "$info" ]; then
        ok "$vol  ${dim}(created: $info)${reset}"
    else
        warn "$vol  — not found (will be created on first container start)"
    fi
done

# If container is running, inspect volume contents
if [ -n "$CONTAINER_ID" ]; then
    section "Volume Contents (survive rebuilds)"

    # NSS repo
    nss_head=$(cexec git -C /workspaces/nss-dev/nss log --oneline -1 2>/dev/null || echo "empty/not cloned")
    kv "nss HEAD:" "$nss_head"

    nss_status=$(cexec git -C /workspaces/nss-dev/nss status --porcelain 2>/dev/null || true)
    if [ -n "$nss_status" ]; then
        nss_changed=$(echo "$nss_status" | wc -l)
        warn "nss: $nss_changed uncommitted change(s)"
    else
        ok "nss: clean working tree"
    fi

    nss_branches=$(cexec git -C /workspaces/nss-dev/nss branch --list 2>/dev/null | grep -v '^\*' | grep -c . || true)
    if [ "${nss_branches:-0}" -gt 0 ]; then
        kv "nss extra branches:" "$nss_branches (besides current)"
    fi

    # NSPR repo
    nspr_head=$(cexec git -C /workspaces/nss-dev/nspr log --oneline -1 2>/dev/null || echo "empty/not cloned")
    kv "nspr HEAD:" "$nspr_head"

    nspr_status=$(cexec git -C /workspaces/nss-dev/nspr status --porcelain 2>/dev/null || true)
    if [ -n "$nspr_status" ]; then
        nspr_changed=$(echo "$nspr_status" | wc -l)
        warn "nspr: $nspr_changed uncommitted change(s)"
    else
        ok "nspr: clean working tree"
    fi

    # ccache stats
    ccache_stats=$(cexec env CCACHE_DIR=/workspaces/nss-dev/.ccache ccache --show-stats 2>/dev/null || echo "unavailable")
    if [ "$ccache_stats" != "unavailable" ]; then
        cache_size=$(echo "$ccache_stats" | grep -i "cache size" | head -1 | sed 's/.*: *//' || echo "?")
        hit_rate=$(echo "$ccache_stats" | grep -i "hit rate" | head -1 | sed 's/.*: *//' || true)
        kv "ccache size:" "$cache_size"
        [ -n "$hit_rate" ] && kv "ccache hit rate:" "$hit_rate"
    fi

    # Build artifacts
    section "Build State (in volumes)"
    dist_exists=$(cexec test -d /workspaces/nss-dev/dist && echo yes || echo no)
    if [ "$dist_exists" = "yes" ]; then
        dist_size=$(cexec du -sh /workspaces/nss-dev/dist 2>/dev/null | cut -f1 || echo "?")
        ok "dist/ exists ($dist_size)"
    else
        kv "dist/:" "not present (no build yet)"
    fi

    out_dir=$(cexec bash -c 'ls -d /workspaces/nss-dev/nss/out/*/ 2>/dev/null | head -5' || true)
    if [ -n "$out_dir" ]; then
        for d in $out_dir; do
            dsize=$(cexec du -sh "$d" 2>/dev/null | cut -f1 || echo "?")
            dname=$(basename "$d")
            kv "nss/out/$dname:" "$dsize"
        done
    else
        kv "nss/out/:" "not present (no build yet)"
    fi

    # Worktrees
    section "Worktrees"
    worktree_list=$(cexec git -C /workspaces/nss-dev/nss worktree list 2>/dev/null || true)
    if [ -n "$worktree_list" ]; then
        # First line is always the main worktree
        main_wt=$(echo "$worktree_list" | head -1)
        kv "main:" "$main_wt"
        extra_wts=$(echo "$worktree_list" | tail -n +2)
        if [ -n "$extra_wts" ]; then
            while IFS= read -r wt; do
                wt_path=$(echo "$wt" | awk '{print $1}')
                wt_rest=$(echo "$wt" | cut -d' ' -f2-)
                wt_name=$(basename "$wt_path")
                kv "$wt_name:" "$wt_rest"
                # Check for uncommitted changes in this worktree
                wt_status=$(cexec git -C "$wt_path" status --porcelain 2>/dev/null || true)
                if [ -n "$wt_status" ]; then
                    wt_changed=$(echo "$wt_status" | wc -l)
                    warn "  $wt_name: $wt_changed uncommitted change(s)"
                fi
                # Check for a matching dist directory
                wt_dist="/workspaces/nss-dev/dist-${wt_name#review-}"
                dist_check=$(cexec du -sh "$wt_dist" 2>/dev/null | cut -f1 || true)
                if [ -n "$dist_check" ]; then
                    kv "  dist:" "$wt_dist ($dist_check)"
                fi
            done <<< "$extra_wts"
        else
            kv "" "No extra worktrees"
        fi
    else
        kv "" "No worktrees (nss repo not cloned?)"
    fi

fi

# --- Bind mounts (host dirs) -------------------------------------------------
section "Bind Mounts (host ↔ container)"

bugs_dir="$PROJ_DIR/bugs"
if [ -d "$bugs_dir" ]; then
    bug_count=$(find "$bugs_dir" -maxdepth 1 -type d -name 'bug-*' 2>/dev/null | wc -l)
    ok "bugs/: $bug_count bug(s) fetched"
    if [ "$bug_count" -gt 0 ]; then
        find "$bugs_dir" -maxdepth 1 -type d -name 'bug-*' -printf '    %f\n' 2>/dev/null | sort
    fi
else
    kv "bugs/:" "directory not found"
fi

claude_dir="$PROJ_DIR/container-claude"
if [ -d "$claude_dir" ]; then
    claude_md="$claude_dir/CLAUDE.md"
    if [ -f "$claude_md" ]; then
        mod_time=$(stat -c '%y' "$claude_md" 2>/dev/null | cut -d. -f1 || echo "?")
        kv "CLAUDE.md modified:" "$mod_time"
    fi
    cmd_count=$(find "$claude_dir/commands" -type f 2>/dev/null | wc -l)
    kv "Commands:" "$cmd_count file(s) in container-claude/commands/"
else
    kv "container-claude/:" "directory not found"
fi

# --- Environment --------------------------------------------------------------
section "Environment"

if [ -f "$PROJ_DIR/.envrc" ]; then
    for key in ANTHROPIC_API_KEY BUGZILLA_API_KEY PHABRICATOR_API_TOKEN; do
        if grep -q "^export $key=" "$PROJ_DIR/.envrc" 2>/dev/null; then
            val=$(grep "^export $key=" "$PROJ_DIR/.envrc" | head -1 | sed 's/^export [^=]*=//' | tr -d '"' | tr -d "'")
            if [ -n "$val" ]; then
                ok "$key is set (${val:0:4}...)"
            else
                warn "$key is empty"
            fi
        else
            warn "$key not found in .envrc"
        fi
    done
else
    warn ".envrc not found — run host-tools/setup-envrc.sh"
fi

echo ""
