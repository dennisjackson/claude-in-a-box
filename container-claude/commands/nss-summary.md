---
name: nss-summary
description: Summarize the current state of all bugs in the bugs/ folder. Reads each bug's LOG.md, checks for missing artifacts, and recommends next steps.
version: 1.0.0
---

# NSS Bug Summary

Read the current state of every active bug in `/workspaces/nss-dev/bugs/` and produce a concise status dashboard.

## Step 1: Discover all bugs

Find all active bug directories

```sh
ls -d /workspaces/nss-dev/bugs/[0-9]*/ 2>/dev/null
```

Skip any bugs in `bugs/finished/` — they are done and need no further action. Only process active bugs (directly under `bugs/`).

## Step 2: For each bug, gather state

**IMPORTANT: Do all data gathering yourself using Read, Glob, Grep, and Bash tools directly. Do NOT delegate per-bug research to subagents — they may miss files or report incorrect results.**

For each bug directory:
1. Read `input/bug.md` — extract the bug title/summary (first heading or title field). This is the one-line description.
2. Read `LOG.md` — the full log. The **last entry** is the current state.
3. List reports that exist:
   ```sh
   ls /workspaces/nss-dev/bugs/BUGDIR/reports/ 2>/dev/null
   ```
4. Check if `input/` exists and has content:
   ```sh
   ls /workspaces/nss-dev/bugs/BUGDIR/input/ 2>/dev/null
   ```
5. Check if any exchange branches exist for this bug number:
   ```sh
   git -C /workspaces/nss-dev/.nss-exchange.git branch --list "*BUGNUM*" 2>/dev/null
   ```
6. Check if any worktrees exist for this bug:
   ```sh
   git -C /workspaces/nss-dev/nss worktree list | grep -i "BUGNUM" 2>/dev/null
   ```

You can batch the `ls` and `git` commands for all bugs in parallel to be efficient.


## Step 3: Sanity checks

For each active bug, flag issues:
- **Missing LOG.md** — every bug should have one after fetch.
- **Missing input/** — bug data not fetched?
- **Log mentions triage but no `reports/triage-report.md`** — report may have failed or been deleted.
- **Log mentions bugfix but no `reports/bugfix-report.md`** — same.
- **Worktree exists but no commits on an exchange branch** — work in progress, not yet delivered.
- **Exchange branch exists but no log entry about it** — log may be stale.

## Step 4: Infer stage and recommend next step

For each bug, determine its workflow stage from the log and available artifacts:

| Stage | Indicators | Recommended next step |
|---|---|---|
| **fetched** | Has `input/`, no triage report, log only shows fetch | Run `/nss-triage` |
| **triaged** | Has `reports/triage-report.md`, log has triage entry | Human reviews triage, then run analysis or `/nss-bugfix` |
| **fix-in-progress** | Worktree exists, no exchange branch yet | Continue work in worktree |
| **patch-ready** | Exchange branch exists | Human reviews: `host-tools/sync-host-nss.sh` on host |
| **reviewed** | Has `reports/review.md` or log mentions review | Address review feedback or finalize |

If the stage is ambiguous, say so and explain what's unclear.

## Step 5: Output

Print a summary table, then details for any bugs with warnings. Format:

```
## Active Bugs

| Bug | Description | Severity | Stage | Last Activity | Next Step |
|-----|-------------|----------|-------|---------------|-----------|
| ... | ...         | ...      | ...   | ...           | ...       |

## Finished: [N] bugs in finished/

## Warnings

- Bug NNNNN: [warning message]
```

- **Severity** comes from the triage report or log entry (e.g., "High", "sec-moderate"). Write "untriaged" if no triage has been done.
- **Last Activity** is the timestamp and short description from the last LOG.md entry.
- Keep the output concise. Don't reproduce full log contents — just the last entry and the recommendation.
