---
name: nss-comment
description: Generate a proposed Bugzilla comment for a security bug. Reads all context, then drafts a minimal comment containing only genuine new insight (not status updates or fix descriptions). Use when the user says "/nss-comment BUGNUM" or similar.
version: 1.0.0
---

# NSS Bug Comment

Generate a proposed Bugzilla comment for: $ARGUMENTS

Follow each phase below in order. Be terse throughout — this is a comment-drafting tool, not an analysis tool. If anything is ambiguous or unclear, **stop and ask the user** before continuing.

**Before starting**, record the wall-clock start time:
```sh
date -u +%s
```

---

## Phase 0: Read the Bug

### 0a. Parse arguments

Parse `$ARGUMENTS` to extract a bug number. Accepted forms: `1234567`, `bug-1234567`, `bug 1234567`. If `$ARGUMENTS` is empty, use the latest folder under `/workspaces/nss-dev/bugs/` sorted by name.

Set `BUGNUM` to the bug number.

### 0b. Locate the bug folder

```sh
BUG_DIR=$(ls -d /workspaces/nss-dev/bugs/*${BUGNUM}*/ 2>/dev/null | head -1)
```

If no match is found, **stop and ask the user** to fetch the bug data first.

### 0c. Check for existing proposed comments

```sh
ls "$BUG_DIR/proposed-comments.md" 2>/dev/null
```

If `proposed-comments.md` already exists, read it in full and **ask the user** whether they want to remove it before proceeding. If they say yes, delete it and continue as if it didn't exist. If they say no, **stop** — do not overwrite or append without explicit permission. The new comment will always be written as the sole content of `proposed-comments.md`, replacing any previous version.

---

## Phase 1: Gather All Context

Read all of the following. Do this yourself — do NOT delegate to subagents.

### 1a. Bug input

- `$BUG_DIR/input/bug.md` — bug metadata (title, severity, status, priority)
- `$BUG_DIR/input/comments.md` — all existing Bugzilla comments (the conversation so far)
- All files in `$BUG_DIR/input/attachments/` — patches, test cases, crash logs

### 1b. Reports

Read every file in `$BUG_DIR/reports/`:
```sh
ls "$BUG_DIR/reports/" 2>/dev/null
```

Read each report in full. These contain the analysis, triage, bugfix, review, and other findings that the comment should draw from.

### 1c. Activity log

Read `$BUG_DIR/LOG.md` in full. This is the chronological record of all work done on the bug.

### 1d. Previously proposed comments

If `proposed-comments.md` existed and the user chose to keep it in 0c, you should have stopped. If the user chose to remove it, it's gone — proceed without it.

### 1e. Worktree and branch state

Check for worktrees and exchange branches related to this bug:

```sh
# Active worktrees
git -C /workspaces/nss-dev/nss worktree list 2>/dev/null | grep -i "$BUGNUM"

# Exchange branches
git -C /workspaces/nss-dev/.nss-exchange.git branch --list "*${BUGNUM}*" 2>/dev/null
```

If a worktree exists, check its branch and recent commits:
```sh
# Substitute the actual worktree path from the previous output
cd <worktree-path>
git log --oneline -10
git diff --stat HEAD
```

If an exchange branch exists, check what it contains:
```sh
git -C /workspaces/nss-dev/.nss-exchange.git log --oneline -10 <branch-name>
```

---

## Phase 2: Determine What's New

Compare the existing Bugzilla comments (`input/comments.md`) against the reports, log, and worktree state. Identify **only genuinely new insight** — information that changes understanding of the bug, narrows/widens the attack surface, or corrects something in the original report.

Things that count as new insight:
- Corrections to the original root cause or severity assessment
- Attack surface changes (paths that are/aren't reachable, configurations that matter)
- Surprising constraints or mitigations not mentioned in the original report
- Systemic findings — the same pattern exists elsewhere

Things that are **NOT** new insight (do not include these):
- Confirming what the report already says (e.g., "confirmed sec-high" when it's already tagged sec-high)
- Restating the root cause that Comment 0 already explained
- Generic status updates ("patch available", "tests pass", "sanitizers clean") — the reviewer can see the patch on Phabricator
- Fix approach descriptions — the reviewer will read the diff
- Test methodology or verification details

If there is **nothing new** beyond what the Bugzilla thread already contains, **stop and tell the user** there is nothing to comment on.

---

## Phase 3: Ask for Clarification if Needed

Before drafting, check for ambiguity:

- If the triage and bugfix reports disagree on severity or root cause, **ask the user** which is correct.
- If it's unclear whether a fix has been finalized or is still in progress, **ask the user**.
- If the LOG.md contains entries that suggest the user has opinions or corrections not reflected in reports, **ask the user** what they want included.
- If you're unsure what level of detail is appropriate (e.g., whether to include specific code references), **ask the user**.

If nothing is ambiguous, proceed directly to Phase 4.

---

## Phase 4: Draft the Comment

The comment should be **as short as possible**. A good Bugzilla comment on a security bug is often 2-5 sentences. It contains only what changes the reader's understanding.

### Rules

- **Only new insight.** Do not restate the root cause, confirm what's already known, or summarize the fix approach (the reviewer will read the diff). If the only "new" thing is that a patch exists, the comment is probably just one sentence pointing to it, or maybe not needed at all.
- **No structure for short comments.** If the comment is under ~5 sentences, write it as plain prose. No headers, no bullet lists, no labeled sections.
- **No generic status.** Do not mention that tests pass, sanitizers are clean, or fuzzing found nothing — unless a specific result is surprising or noteworthy (e.g., "fuzzing found a second variant" or "UBSan flagged an unrelated issue in the same function").
- **No fix descriptions.** The reviewer reads the diff. Don't describe what the patch does unless there's a non-obvious design choice that needs justification.
- **Audience.** Mozilla security engineers who know NSS. Never explain basics.
- **Tone.** Match existing comments. Typically terse, direct, technical. No greetings or sign-offs.

---

## Phase 5: Write Output

### 5a. Write the proposed comment

Write to `$BUG_DIR/proposed-comments.md`, replacing any existing content (the user already approved removal in Phase 0c if the file existed).

Format:

```markdown
# Proposed Comment for Bug NNNNNN

<the drafted comment text, exactly as it should be posted to Bugzilla>
```

### 5b. Present the comment for review

After writing the file, display the full text of the proposed comment to the user. Tell them:
- The file path where it was saved
- That they should review and edit before posting to Bugzilla
- If there are any caveats or things you were uncertain about, flag them explicitly

### 5c. Update the log

Append a one-line entry to `$BUG_DIR/LOG.md`:

```
- YYYY-MM-DD HH:MM UTC — /nss-comment: drafted proposed Bugzilla comment (<brief description of what the comment covers>)
```

Use `date -u` for the timestamp:
```sh
NOW=$(date -u +"%Y-%m-%d %H:%M UTC")
echo "- $NOW — /nss-comment: drafted proposed Bugzilla comment (<brief description>)" >> "$BUG_DIR/LOG.md"
```

---

## Notes

- This command is **read-only with respect to code**. It does not modify any source files or worktrees. It only writes to `proposed-comments.md` and appends to `LOG.md`.
- If the user asks for changes to the drafted comment, edit `proposed-comments.md` directly and show the updated version.
- The comment is **not posted automatically**. The user will review it and post it manually to Bugzilla.
