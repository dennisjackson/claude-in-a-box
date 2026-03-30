---
name: nss-bugfix
description: Investigate and fix an NSS/NSPR bug. Use when the user says "/nss-bugfix BUGNUM", "fix bug XXXXX", or similar. Reads bug reports from bugs/, writes a reproducer (gtest or fuzzer), develops a minimal fix, verifies it, and checks for systemic variants.
version: 1.0.0
disable-model-invocation: true
---

# NSS Bug Fix

Fix bug: $ARGUMENTS

Follow each phase below in order. Be terse: if a phase completes without issues, just record the outcome and move on. Only provide detail when something fails, is ambiguous, or needs the user's attention.

**Report requirement**: You MUST write the report file when you complete the final phase. If the user continues the conversation and subsequent discussion reveals new information — corrections, additional findings, revised severity, better understanding of root cause — update the report file to reflect the current best understanding. The report should always represent the most accurate and complete picture available.

**Before starting**, record the wall-clock start time:
```sh
date -u +%s
```

---

## Phase 0: Set Up Worktree

### 0a. Parse arguments

Parse `$ARGUMENTS` to extract one or more bug numbers. Accepted forms: `1234567`, `bug-1234567`, `bug 1234567`. If multiple bugs are given, process them together (they may be related).

Set `BUGNUM` to the primary bug number (first one given, or only one). If `$ARGUMENTS` is empty, use the latest folder under `/workspaces/nss-dev/bugs/` sorted by name.

### 0b. Create worktree

```sh
WORKTREE_NAME=fix-$BUGNUM
WORKTREE_DIR=/workspaces/nss-dev/worktrees/$WORKTREE_NAME
NSS_DIST_DIR=/workspaces/nss-dev/dist-$WORKTREE_NAME

mkdir -p /workspaces/nss-dev/worktrees

if [ -d "$WORKTREE_DIR" ]; then
  echo "Reusing existing worktree: $WORKTREE_DIR"
else
  echo "Creating worktree: $WORKTREE_DIR"
  git -C /workspaces/nss-dev/nss worktree add --detach "$WORKTREE_DIR" \
    || git -C /workspaces/nss-dev/nss worktree add --force --detach "$WORKTREE_DIR"
fi

NSS_DIR=$WORKTREE_DIR
ln -sfn /workspaces/nss-dev/nspr /workspaces/nss-dev/worktrees/nspr

echo "NSS_DIR:      $NSS_DIR"
echo "NSS_DIST_DIR: $NSS_DIST_DIR"
```

All subsequent phases use `$NSS_DIR` and `$NSS_DIST_DIR`. The main checkout at `/workspaces/nss-dev/nss` is never touched.

---

## Phase 1: Investigate the Bug

### 1a. Read the bug report

Locate the bug folder. Check both `/workspaces/nss-dev/bugs/$BUGNUM/` and `/workspaces/nss-dev/bugs/bug-$BUGNUM/` — use whichever exists. If neither exists, **stop and ask the user** to fetch the bug data first (e.g., by providing the bug folder or running the bug fetch tool). Do not proceed without bug context.

Once located, set `BUG_DIR` to the path and read everything available:
- `index.md` or any markdown summary — read in full
- All files in `attachments/` — read patches, test cases, crash logs, stack traces
- If multiple bugs were given, read all of them

### 1b. Identify the core issue(s)

Based on the bug report, comments, and any attachments, determine:

1. **Root cause**: What is the underlying defect? (e.g., buffer overread, use-after-free, integer overflow, missing validation, logic error, race condition)
2. **Trigger condition**: What input, state, or sequence triggers the bug? (e.g., malformed TLS extension, specific certificate chain, particular API call sequence)
3. **Affected code**: Which file(s) and function(s) contain the defect? Read the relevant source files in the worktree to confirm.
4. **Security impact**: None / Low / Medium / High / Critical — with brief justification.
5. **Severity of the fix**: Is this a one-line fix, a localized change, or does it require structural changes?

Read the actual source code in the worktree to confirm your understanding. Use `weggli`, `grep`, or direct file reads as needed to trace the code paths involved.

### 1c. Check for existing patches

If the bug folder contains `.diff` or `.patch` files in `attachments/`, read and evaluate them. These may contain a proposed fix from the bug reporter or another developer.

**Ask the user how to proceed.** Present a concise assessment of the proposed patch (correct / partially correct / incorrect, with reasoning) and ask whether to:
1. **Apply and verify** the existing patch (if it looks correct — skip to Phase 4 after applying)
2. **Use as a starting point** and improve it (if partially correct)
3. **Develop an independent fix** (if the patch is wrong or the user prefers a fresh approach)

Do not apply or ignore proposed patches without the user's input.

Print a concise summary of your findings:
- Root cause (1-2 sentences)
- Trigger condition (1 sentence)
- Affected files and functions
- Security impact assessment

---

## Phase 2: Write a Reproducer

Before writing any test code, verify the worktree builds cleanly on its own:
```sh
cd "$NSS_DIR"
NSS_DIST_DIR="$NSS_DIST_DIR" ./build.sh 2>&1 | tail -20
```
If the build fails, diagnose and fix the build issue first (it may be an environment problem, not a code problem). Do not proceed until the baseline builds.

The goal is to create a test that **demonstrates the bug on unfixed code** (fails or crashes before the fix, passes after). Choose the most appropriate approach in this order of preference:

### Option A: GTest (preferred)

If the bug can be reproduced with a targeted test case that requires roughly **50 lines or less** of new code (beyond what the suite already provides):

1. Identify the correct gtest suite. Match the affected library to its test suite:
   - `lib/ssl/` → `$NSS_DIR/gtests/ssl_gtest/` (run via `ssl_gtests/ssl_gtests.sh`)
   - `lib/pk11wrap/` → `$NSS_DIR/gtests/pk11_gtest/` (run via `pk11_gtests/pk11_gtests.sh`)
   - `lib/certdb/` → `$NSS_DIR/gtests/certdb_gtest/`
   - `lib/mozpkix/` → `$NSS_DIR/gtests/mozpkix_gtest/`
   - `lib/util/` (DER/encoding) → `$NSS_DIR/gtests/der_gtest/`
   - `lib/freebl/` → `$NSS_DIR/gtests/freebl_gtest/`
   - `lib/softoken/` → `$NSS_DIR/gtests/softoken_gtest/`
   - `lib/smime/` → `$NSS_DIR/gtests/smime_gtest/`
   - Check `ls $NSS_DIR/gtests/` for additional suites if the above don't match.

2. Read existing tests in the relevant suite to understand the test patterns and helpers available.

3. Write a minimal test that:
   - Sets up the specific trigger condition identified in Phase 1
   - Exercises the buggy code path
   - Has a clear assertion that fails when the bug is present and passes when fixed
   - Follows the naming convention of the existing tests in that suite

4. Build and run the test to confirm it fails (demonstrating the bug):
   ```sh
   cd "$NSS_DIR"
   NSS_DIST_DIR="$NSS_DIST_DIR" ./build.sh 2>&1 | tail -20

   cd "$NSS_DIR/tests"
   HOST=localhost DOMSUF=localdomain USE_64=1 DIST="$NSS_DIST_DIR" \
     GTESTFILTER="<TestSuite>.<TestName>" bash <suite>_gtests/<suite>_gtests.sh 2>&1 \
     | tee /tmp/reproducer-run.log | tail -15
   ```

5. Confirm the test fails. If it passes, the test does not reproduce the bug — revisit the trigger condition.

If the test would require more than ~50 lines of new setup/helpers, consider whether the framework investment is justified: more code is acceptable if it introduces reusable helpers that would support writing many similar tests (e.g., a harness for injecting malformed extensions). This is rare — in most cases, prefer Option B instead.

### Option B: Fuzzer

If the bug is better demonstrated by fuzzing (e.g., it requires specific malformed input that is hard to construct manually, or it was originally found by a fuzzer):

1. Check if an existing fuzzer target covers the affected code path:
   ```sh
   ls "$NSS_DIR/fuzz/"
   ```

2. If an existing target is close but needs modification, extend it. If no suitable target exists, consider writing a new one (check `$NSS_DIR/fuzz/` for the pattern).

3. If the bug report includes a crash input or reproducer file, use it:
   ```sh
   cd "$NSS_DIR"
   NSS_DIST_DIR="$NSS_DIST_DIR" ./build.sh --fuzz --disable-tests --asan 2>&1 | tail -20
   # or --fuzz=tls for TLS/DTLS targets

   "$NSS_DIST_DIR/Debug/bin/nssfuzz-<target>" /path/to/crash-input
   ```

4. If no crash input is available, run the fuzzer briefly to see if it finds the issue:
   ```sh
   "$NSS_DIST_DIR/Debug/bin/nssfuzz-<target>" -max_total_time=60 -artifact_prefix=/tmp/fuzz-repro-
   ```

### Option C: Other approaches

If neither a gtest nor a fuzzer is practical (e.g., the bug requires a specific network interaction, timing-dependent race condition, or complex multi-process setup):

1. Explain why options A and B are not feasible.
2. Suggest alternative approaches (e.g., a shell-based test using NSS tools like `tstclnt`/`selfserv`, a manual reproduction procedure, or a targeted code review).
3. **Ask the user for input** before proceeding. Do not guess — the user may have context about how to reproduce the issue.

Record what you chose and whether the reproducer successfully demonstrates the bug.

---

## Phase 3: Develop the Fix

### 3a. Design the fix

Before writing code, state your approach:
- What specifically needs to change and why
- Why this fix is correct (not just suppressing symptoms)
- Any edge cases or invariants that must be preserved

**If there are multiple plausible approaches**, or if the root cause is unclear, **ask the user** which approach they prefer before writing code. Present the options concisely with pros/cons.

### 3b. Implement the fix

Write the minimal, self-contained fix. Guidelines:
- **Minimal**: Change only what is necessary to fix the bug. Do not refactor surrounding code, add unrelated improvements, or "clean up" while you're here.
- **Self-contained**: The fix should be understandable on its own. If a comment is needed to explain a non-obvious invariant, add one.
- **Clearly correct**: Prefer simple, obviously-right solutions over clever ones. The reviewer should be able to verify correctness by inspection.
- **Defense in depth is acceptable** if clearly justified — e.g., adding a bounds check even if the caller "should" never pass a bad value, but only if the justification is real (not speculative).
- **Minimal comments**: Do not add bug-specific comments in code or tests. Only comment to capture high-level intent or explain surprising behavior. The commit message is the right place for bug context.

Make the changes in the worktree:
```sh
cd "$NSS_DIR"
# Edit the relevant files
```

### 3c. Check formatting

Run clang-format on all modified files:
```sh
cd "$NSS_DIR"
git diff --name-only -- '*.c' '*.cc' '*.cpp' '*.h' | while read -r f; do
  clang-format --dry-run --Werror "$f" 2>&1
done
```
Fix any formatting issues before proceeding.

---

## Phase 4: Verify the Fix

### 4a. Build and run the reproducer

Build with sanitizers and confirm the reproducer now passes:
```sh
cd "$NSS_DIR"
NSS_DIST_DIR="$NSS_DIST_DIR" ./build.sh -c --ubsan --asan 2>&1 | tail -30
```

Run the reproducer test:
```sh
cd "$NSS_DIR/tests"
HOST=localhost DOMSUF=localdomain USE_64=1 DIST="$NSS_DIST_DIR" \
  GTESTFILTER="<TestSuite>.<TestName>" bash <suite>_gtests/<suite>_gtests.sh 2>&1 \
  | tee /tmp/fix-verify.log | tail -15
```

Expected: the test passes with no sanitizer errors.

**If the reproducer still fails or sanitizers flag issues**, return to Phase 3 and iterate on the fix. Diagnose what went wrong — read the test output and sanitizer messages carefully. Try at least two different approaches before asking the user for help.

### 4b. Run broader tests

Run the broader test suite for the affected subsystem to check for regressions:
```sh
cd "$NSS_DIR/tests"
HOST=localhost DOMSUF=localdomain USE_64=1 DIST="$NSS_DIST_DIR" \
  bash <suite>_gtests/<suite>_gtests.sh 2>&1 \
  | tee /tmp/regression-run.log | tail -15
grep -E "^\[  FAILED  \]" /tmp/regression-run.log | head -20
```

If the fix touches core crypto or certificate code, consider running additional test suites (e.g., `cert/cert.sh`, `ssl/ssl.sh`).

### 4c. Fuzz briefly (if relevant)

If the bug was fuzz-related or the fix touches parser/decoder code:
```sh
cd "$NSS_DIR"
NSS_DIST_DIR="$NSS_DIST_DIR" ./build.sh --fuzz=tls --disable-tests --asan 2>&1 | tail -20

"$NSS_DIST_DIR/Debug/bin/nssfuzz-<target>" -max_total_time=30 2>&1 | tail -10
```

---

## Phase 5: Systemic Analysis

This phase looks beyond the immediate fix for related issues. Do NOT write code in this phase — only investigate and report.

### 5a. Alternative triggers

Could the same bug be triggered through a different code path? Search for:
- Other callers of the affected function
- Other code that parses the same data structure or protocol message
- DTLS variants if the bug is in TLS (and vice versa)
- Different handshake modes (PSK, 0-RTT, HRR, resumption) if the bug is in handshake code

```sh
# Example: find other callers
cd "$NSS_DIR"
grep -rn "function_name" lib/ --include='*.c' --include='*.h'
```

### 5b. Same pattern elsewhere

Does the same class of mistake appear in other parts of the codebase? Search for:
- Similar patterns using `weggli` or `grep` (e.g., if the bug was a missing length check, search for similar unchecked lengths)
- Code written by the same pattern (e.g., other extension parsers, other message handlers in the same file)
- Recently changed code in the same subsystem

```sh
# Example: find similar patterns with weggli
weggli '<pattern>' "$NSS_DIR/lib/"
```

### 5c. Report findings

For each potential issue found, note:
- File and function
- Why it looks similar to the original bug
- Whether it's definitely a bug or just suspicious
- Severity estimate

**Present these findings to the user.** Do not fix them — they may be intentional, already known, or out of scope. Let the user decide what to do.

---

## Phase 6: Commit, Push, and Report

### 6a. Create a descriptive branch

Create a branch with a descriptive name including the bug number:
```sh
cd "$NSS_DIR"
BRANCH_NAME="bug-$BUGNUM-<short-description>"
# e.g. bug-1234567-fix-tls-extension-overread
git checkout -b "$BRANCH_NAME"
```

### 6b. Check for security-sensitive commit messages

Before writing commit messages, assess whether the commit message you would naturally write reveals a security vulnerability. Indicators include:

- Memory safety issues: buffer overread/overwrite, use-after-free, double-free, heap overflow, stack overflow, out-of-bounds access
- Exploitable conditions: integer overflow leading to undersized allocation, type confusion, null dereference in security-critical path
- Crypto weaknesses: timing side-channels, nonce reuse, padding oracle, key material leak
- Any language suggesting attacker-controllable input reaches an unsafe operation

If the natural commit message **would** reveal a security bug, **ask the user** whether they want to use substitute commit messages that are technically accurate but sound more routine. Explain that detailed messages create a gap-attack window — attackers can identify the vulnerability from the commit before the patch is widely deployed.

Present both options side by side:
1. **Transparent message** — the full, specific description (e.g., "Fix heap buffer overread in TLS ClientHello extension parsing")
2. **Innocuous message** — a correct but vague alternative (e.g., "Improve input validation in TLS extension handling")

Use whichever style the user chooses for both the fix commit and the test commit.

### 6c. Commit the fix (patch 1 of 2)

Commit **only the production code fix** — no test files. Stage the specific files that constitute the fix:
```sh
cd "$NSS_DIR"
# Stage only the fix files (lib/, cmd/, etc. — NOT gtests/ or fuzz/)
git add <fix-files...>
git commit -m "$(cat <<'EOF'
Bug BUGNUM - <short description of fix> r=#nss-reviewers

<1-2 sentence explanation of what was wrong and what this patch does>
EOF
)"
```

### 6d. Commit the test (patch 2 of 2)

Commit the reproducer test as a separate patch:
```sh
cd "$NSS_DIR"
git add -A
git commit -m "$(cat <<'EOF'
Bug BUGNUM - Add test for <short description> r=#nss-reviewers

<1 sentence describing what the test verifies>
EOF
)"
```

### 6e. Write a summary report

**Record the end time:**
```sh
date -u +%s
```
Calculate elapsed wall-clock time from the start time recorded before Phase 0.

Create the directory if needed and write the report:
```sh
mkdir -p /workspaces/nss-dev/bugs/$BUGNUM
```

Write the report to `/workspaces/nss-dev/bugs/$BUGNUM/bugfix-report.md`:

```
# NSS Bug <BUGNUM> — Fix Report

**Worktree**: <worktree path>
**Branch**: <branch name pushed to exchange remote>
**Commits**: <number of commits (typically 2: fix + test)>

## Bug Summary

**Root cause**: [1-2 sentences]
**Trigger**: [1 sentence]
**Security impact**: [None / Low / Medium / High / Critical — with justification]

## Reproducer

**Type**: [gtest / fuzzer / other]
**Location**: [file path and test name]
**Confirms bug**: [Yes — test fails on unfixed code / No — could not reproduce]

## Fix

**Approach**: [1-2 sentences describing what was changed and why]
**Files changed**:
- [file1 — what changed]
- [file2 — what changed]

**Defense in depth**: [Any additional hardening added, with justification, or "None"]

## Verification

| Check | Result |
|---|---|
| Reproducer passes | [Yes / No] |
| Sanitizers (UBSan+ASan) | [Clean / findings] |
| Regression tests | [Pass / failures] |
| Fuzzing | [N/A / Clean / findings] |

## Systemic Analysis

**Alternative triggers**: [List or "None found"]
**Same pattern elsewhere**: [List with file:line references, or "None found"]
**Recommendations**: [Any suggested follow-up actions]

## Timing

| Metric | Value |
|---|---|
| Wall time | [Xm Ys] |
```

After writing the report, print:
1. The branch name and worktree path where the commits live.
2. The path to the saved report file.
3. A brief summary of the fix and any systemic findings.
4. Tell the user they can push to the host when ready:
   ```
   git push exchange <branch-name>
   ```
5. Remind the user the worktree can be cleaned up with:
   ```sh
   git -C /workspaces/nss-dev/nss worktree remove $WORKTREE_DIR
   rm -rf $NSS_DIST_DIR
   ```
