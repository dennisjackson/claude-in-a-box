---
name: nss-review
description: Review an NSS/NSPR bug patch. Use when the user says "/nss-review BUGNUM", "review bug XXXXX", "review patch for bug", "review patches in worktree <name>", or similar. Performs full patch validation including test verification, sanitizer builds, fuzzing, and coverage analysis.
version: 1.5.0
disable-model-invocation: true
---

# NSS Bug Patch Review

Review bug: $ARGUMENTS

Follow each phase below in order. Be terse: if a phase completes without issues, just record "No issues" and move on. Only provide detail when something fails, looks suspicious, or needs the user's attention.

**Before starting**, record the wall-clock start time:
```sh
date -u +%s
```

---

## Phase 0: Locate the Diff

### 0a. Determine the mode and bug number

Parse `$ARGUMENTS` to determine the review mode:

**Worktree mode** — the argument mentions "worktree" or names an existing directory under `/workspaces/nss-dev/worktrees/`:
- Extract the worktree name (e.g., `bug-2026089-review` from "The patches in worktree bug-2026089-review").
- Derive the bug number from the worktree name if possible (e.g., `bug-2026089-review` → bug number `bug-2026089`; strip any trailing `-review` or other suffix after the numeric ID).
- Set `MODE=worktree`, `WORKTREE_NAME=<extracted name>`, `BUGNUM=<derived bug number>`.

**Bug-number mode** — the argument is a raw bug number or `bug-XXXXXXX`:
- Set `MODE=bug`, `BUGNUM=<bug number>`.
- If `$ARGUMENTS` is empty, use the latest folder under `/workspaces/nss-dev/bugs/` sorted by name.

### 0b. Set up the working directory and dist path

**Worktree mode:**
```sh
NSS_DIR=/workspaces/nss-dev/worktrees/$WORKTREE_NAME
NSS_DIST_DIR=/workspaces/nss-dev/dist-$WORKTREE_NAME

# Verify the worktree exists
if [ ! -d "$NSS_DIR" ]; then
  echo "ERROR: worktree $NSS_DIR does not exist — check the name and try again"
  exit 1
fi

# Ensure NSPR symlink exists
ln -sfn /workspaces/nss-dev/nspr /workspaces/nss-dev/worktrees/nspr

echo "MODE:         worktree"
echo "NSS_DIR:      $NSS_DIR"
echo "NSS_DIST_DIR: $NSS_DIST_DIR"
```

**Bug-number mode:**
```sh
WORKTREE_DIR=/workspaces/nss-dev/worktrees/review-$BUGNUM
NSS_DIST_DIR=/workspaces/nss-dev/dist-review-$BUGNUM

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

echo "MODE:         bug"
echo "NSS_DIR:      $NSS_DIR"
echo "NSS_DIST_DIR: $NSS_DIST_DIR"
```

All subsequent phases use `$NSS_DIR` and `$NSS_DIST_DIR`. The main checkout at `/workspaces/nss-dev/nss` and its dist at `/workspaces/nss-dev/dist` are never touched.

### 0c. Obtain the patch diff

**Worktree mode** — generate the diff from the commits in the worktree:
```sh
# Find the common ancestor between the worktree tip and the main checkout tip.
BASE=$(git -C "$NSS_DIR" merge-base HEAD \
       $(git -C /workspaces/nss-dev/nss rev-parse HEAD))
echo "Base commit: $BASE"
echo "Commits on this worktree:"
git -C "$NSS_DIR" log --oneline "$BASE"..HEAD

# Export the cumulative diff as the canonical patch file for this review.
PATCH_FILE=/tmp/review-$WORKTREE_NAME.diff
git -C "$NSS_DIR" diff "$BASE"..HEAD > "$PATCH_FILE"
echo "Patch file: $PATCH_FILE ($(wc -l < $PATCH_FILE) lines)"
```

Also check whether a bug folder exists for additional context (summaries, Bugzilla attachments):
```sh
BUG_DIR=/workspaces/nss-dev/bugs/$BUGNUM
if [ -d "$BUG_DIR" ]; then
  echo "Bug context available at $BUG_DIR"
  ls "$BUG_DIR"
else
  echo "No bugs/ folder found for $BUGNUM — working from worktree commits only"
fi
```

**Bug-number mode** — find patch files in the attachments folder:
```sh
ATTACH_DIR=/workspaces/nss-dev/bugs/$BUGNUM/attachments
ls "$ATTACH_DIR"/*.diff "$ATTACH_DIR"/*.patch 2>/dev/null \
  || { echo "ERROR: no .diff or .patch files found in $ATTACH_DIR"; exit 1; }

# Combine all patch files into a single canonical diff for later phases.
PATCH_FILE=/tmp/review-$BUGNUM.diff
cat "$ATTACH_DIR"/*.diff "$ATTACH_DIR"/*.patch 2>/dev/null > "$PATCH_FILE"
echo "Patch file: $PATCH_FILE"
```

---

## Phase 1: Patch Analysis

Read the full diff at `$PATCH_FILE`. Internally note the files changed, subsystems affected, relevant fuzzers and test suites — you need these to drive later phases. Only output a 1-2 sentence summary of what the patch does. Save detailed file lists for the final report.

If a `bugs/$BUGNUM/index.md` or similar summary file exists, read it for additional context on the bug being fixed.

---

## Phase 2: Test Adequacy Analysis

This phase determines whether the patch's tests actually validate the core issue. Perform this analysis before running any tests so the results of later phases can be evaluated against it.

**2a. Identify the core issue being fixed.**

Read the bug summary (`bugs/$BUGNUM/index.md` if available), the patch diff, and any commit messages. Answer concisely:
- What is the root cause of the bug? (e.g., buffer overread, use-after-free, integer overflow, logic error, missing validation)
- What is the trigger condition? (e.g., a specific TLS message, a malformed certificate, a particular API call sequence)
- What is the security impact? (e.g., crash, information disclosure, authentication bypass, none)

**2b. Identify related security concerns.**

Based on the root cause and the subsystem(s) touched, list any related classes of vulnerability that a thorough reviewer should consider. For example:
- If the fix bounds-checks a length field: are there **other callers** of the same function or **sibling code paths** that parse the same structure and might have the same bug?
- If the fix addresses a TLS state machine issue: could the same mis-transition occur in DTLS, or in a different handshake mode (PSK, 0-RTT, HRR)?
- If the fix null-checks a pointer: could the same pointer be null at **other dereference sites** in the same function or callers?
- If the fix touches memory allocation/free: are there double-free, use-after-free, or leak variants in nearby code?

List 0–5 specific related concerns. Do not fabricate concerns that are not supported by the code — if nothing related stands out, say "No related concerns identified."

**2c. Evaluate whether the provided tests cover the critical issue.**

Examine any new or modified test cases in the patch. For each, answer:
1. **Does it exercise the exact trigger condition?** A test that merely calls the affected function is not sufficient — it must set up the specific input or state that triggers the bug.
2. **Does it verify the correct behaviour under the fix?** (e.g., returns an error code, does not crash, produces expected output)
3. **Does it cover the related concerns from 2b?** If not, note which concerns remain untested.

Produce a short verdict:
- **Tests adequate** — the critical path and key variants are tested.
- **Tests partially adequate** — the critical path is tested but [specific gaps].
- **Tests inadequate** — the tests do not exercise the actual trigger condition, or no tests are provided for a security-relevant fix.
- **No tests provided** — note whether tests are expected (security fix → tests strongly expected; trivial refactor → may be acceptable).

Record this verdict and the gaps (if any) for the final report. Do not block the review on this — it is an assessment, not a gate.

---

## Phase 3: Pre-Patch Test Verification (Tests Must Fail)

This phase verifies that any new test cases in the patch actually test the bug being fixed.

**Only run this phase if the patch adds new gtest test cases.**

3a. Determine the state of the working tree:

**Worktree mode** — patches are already committed; the working tree should be clean.
To test unfixed code, temporarily check out the base commit, then restore:
```sh
PATCHED_HEAD=$(git -C "$NSS_DIR" rev-parse HEAD)
git -C "$NSS_DIR" checkout "$BASE"
# → proceed to step 3b
# After testing, restore with: git -C "$NSS_DIR" checkout $PATCHED_HEAD
```

**Bug-number mode** — check whether patches are already applied:
```sh
git -C "$NSS_DIR" status
```
- **Clean working tree**: proceed to step 3b directly.
- **Dirty working tree** (patches already applied): stash all changes, then apply only the test-addition patch(es) — i.e. the patch file(s) that only add new test cases without modifying production code:
  ```sh
  git -C "$NSS_DIR" stash
  git -C "$NSS_DIR" apply /path/to/test-only-patch.diff
  ```

3b. Build NSS (standard build):
```sh
cd "$NSS_DIR"
NSS_DIST_DIR="$NSS_DIST_DIR" ./build.sh 2>&1 | tail -20
```

3c. Extract new test names programmatically from the patch diff, then run them in a single invocation:
```sh
GTESTFILTER=$(grep -E '^\+\s*TEST(_F|_P)?\(' "$PATCH_FILE" \
  | sed -E 's/.*TEST(_F|_P)?\(([^,]+),\s*([^)]+)\).*/\2.\3/' \
  | paste -sd ':')
echo "GTESTFILTER=$GTESTFILTER"

cd "$NSS_DIR/tests"
HOST=localhost DOMSUF=localdomain USE_64=1 DIST="$NSS_DIST_DIR" \
  GTESTFILTER="$GTESTFILTER" bash ssl_gtests/ssl_gtests.sh 2>&1 \
  | tee /tmp/pre-patch-run.log | tail -15
grep -E "^\[  FAILED  \]|: Failure$|Expected|Which is:" /tmp/pre-patch-run.log | head -30
```
For other gtest suites, use the appropriate script under `$NSS_DIR/tests/`.

After testing, restore the patched state:
- **Worktree mode**: `git -C "$NSS_DIR" checkout $PATCHED_HEAD`
- **Bug-number mode** (stashed): `git -C "$NSS_DIR" stash pop`

**Expected outcome**: New test cases should FAIL here (they test the bug being fixed). Only report detail if tests unexpectedly pass. If they fail as expected, say "New tests fail on unfixed code as expected."

---

## Phase 4: Apply the Patch

**Worktree mode** — patches are already committed; nothing to apply. Confirm:
```sh
git -C "$NSS_DIR" log --oneline "$BASE"..HEAD
```
Record the commit summary and move on.

**Bug-number mode:**

If the working tree is clean (patches not yet applied, or just restored from stash in Phase 3):
```sh
cd "$NSS_DIR"
git apply --check "$PATCH_FILE"   # dry run first
git apply "$PATCH_FILE"
```

If Phase 3 stashed the original changes: restore the full set of patches via `git stash pop` instead of re-applying manually.

If there are multiple patch files in bug-number mode: apply them in dependency order (fix patch first, then additional test patches, or combined if independent).

If `git apply` fails, try `patch -p1 < "$PATCH_FILE"`. Record any apply errors or conflicts.

---

## Phase 5: clang-format Check

Check that all modified C/C++ source files in the patch conform to NSS formatting rules. Run `clang-format --dry-run --Werror` on only the files changed by the patch. This avoids modifying the working tree and cleanly separates patch violations from pre-existing ones.

**Worktree mode** — diff is between commits, so use the base..HEAD range:
```sh
cd "$NSS_DIR"
git diff "$BASE"..HEAD --name-only -- '*.c' '*.cc' '*.cpp' '*.h' | while read -r f; do
  clang-format --dry-run --Werror "$f" 2>&1
done
```

**Bug-number mode** — diff is in the working tree:
```sh
cd "$NSS_DIR"
git diff --name-only -- '*.c' '*.cc' '*.cpp' '*.h' | while read -r f; do
  clang-format --dry-run --Werror "$f" 2>&1
done
```

If any file exits non-zero, clang-format prints the reformatting warnings. Record violations (file name + line range is sufficient) and note whether they are in newly added lines or pre-existing. No `git restore` is needed since `--dry-run` does not modify files.

---

## Phase 6: Build and Test (UBSan + ASan combined)

UBSan and ASan can be enabled together in a single build. Build once, run the relevant tests once, and record results for both sanitizers.

The relevant tests are those identified in Phase 1; for ssl_gtest use a `GTESTFILTER`, for other suites use the appropriate script under `$NSS_DIR/tests/`.

**Build with both sanitizers:**
```sh
cd "$NSS_DIR"
NSS_DIST_DIR="$NSS_DIST_DIR" ./build.sh -c --ubsan --asan 2>&1 | tail -30
```
If the build succeeds cleanly, say "Build OK." Only show output on failure or warnings in changed files.

**Run relevant tests** (reuse the `GTESTFILTER` extracted in Phase 3, or extract it now if Phase 3 was skipped):
```sh
if [ -z "$GTESTFILTER" ]; then
  GTESTFILTER=$(grep -E '^\+\s*TEST(_F|_P)?\(' "$PATCH_FILE" \
    | sed -E 's/.*TEST(_F|_P)?\(([^,]+),\s*([^)]+)\).*/\2.\3/' \
    | paste -sd ':')
fi

cd "$NSS_DIR/tests"
HOST=localhost DOMSUF=localdomain USE_64=1 DIST="$NSS_DIST_DIR" \
  GTESTFILTER="$GTESTFILTER" bash ssl_gtests/ssl_gtests.sh 2>&1 \
  | tee /tmp/post-patch-run.log | tail -15
grep -E "^\[  FAILED  \]|: Failure$|Expected|Which is:" /tmp/post-patch-run.log | head -30
```

Expected: all tests pass. If they do and no sanitizer errors appear, say "All tests pass. No sanitizer issues." Only report detail on failures or sanitizer findings.

---

## Phase 7: Fuzzing (Brief)

Only run fuzzers identified as relevant in Phase 1. Skip this phase if no relevant fuzzers were identified.

Build with fuzzing support. For TLS/DTLS client and server fuzzers, use `--fuzz=tls` (Totally Lacking Security mode); for all other targets, use `--fuzz`:
```sh
cd "$NSS_DIR"
NSS_DIST_DIR="$NSS_DIST_DIR" ./build.sh --fuzz=tls --disable-tests 2>&1 | tail -20
```

Fuzz binaries are named `nssfuzz-<target>` under `$NSS_DIST_DIR/Debug/bin/`. List available targets first if unsure:
```sh
ls "$NSS_DIST_DIR/Debug/bin/nssfuzz-"*
```

For each relevant fuzzer target, run for 30 seconds:
```sh
TARGET=tls-client   # e.g. tls-client, tls-server, dtls-client, dtls-server, ech
"$NSS_DIST_DIR/Debug/bin/nssfuzz-$TARGET" \
  -max_total_time=30 -artifact_prefix=/tmp/fuzz-$TARGET- 2>&1 | tail -10
```

If no crashes are found, say "No crashes (Xk exec/s)." Only report detail on crashes or anomalies.

---

## Phase 8: Coverage Check

Use `./mach test-coverage` for unit-test line coverage. Do not attempt to pass coverage flags directly to `build.sh` — that approach does not work.

**Run coverage and capture the LCOV path:**
```sh
cd "$NSS_DIR"
./mach test-coverage --test ssl_gtests 2>&1 | tee /tmp/coverage-run.log | tail -10
LCOV_FILE=$(grep "Coverage LCOV data:" /tmp/coverage-run.log | awk '{print $NF}')
echo "LCOV: $LCOV_FILE"
```

**Use diff-cover to focus on lines changed by the patch:**
```sh
mkdir -p /workspaces/nss-dev/bugs/$BUGNUM
COVERAGE_REPORT=/workspaces/nss-dev/bugs/$BUGNUM/coverage-report.html
diff-cover "$LCOV_FILE" \
  --diff-file "$PATCH_FILE" \
  --html-report "$COVERAGE_REPORT" \
  2>&1
echo "Coverage report: $COVERAGE_REPORT"
```

diff-cover prints a per-file summary of what percentage of lines added/changed by the patch are covered. If coverage looks adequate for the changed files, say "Coverage adequate for changed files." Only call out specific uncovered lines if they look like they should be tested.

If `diff-cover` is not installed or the build fails, say "Skipped — [reason]" and move on.

---

## Phase 9: Review Summary

Produce a compact review report. For phases with no issues, use a single "No issues" line — do not repeat the details. Only expand on phases that found real problems.

**Record the end time:**
```sh
date -u +%s
```
Calculate elapsed wall-clock time from the start time recorded before Phase 0.

Write the report to `/workspaces/nss-dev/bugs/$BUGNUM/review.md`. Create the directory if it does not exist:
```sh
mkdir -p /workspaces/nss-dev/bugs/$BUGNUM
```

Report format:

```
# NSS Bug <BUGNUM> — Patch Review

**Patch**: [1-2 sentence description]
**Files**: [list of changed files]
**Mode**: [worktree: <name> / bug attachments]
**Verdict**: [APPROVE / NEEDS WORK / NEEDS DISCUSSION]

## Core Issue

**Root cause**: [1 sentence — e.g., buffer overread in TLS extension parsing]
**Trigger**: [1 sentence — e.g., malformed SNI extension with zero-length hostname]
**Security impact**: [None / Low / Medium / High — with brief justification]

## Test Adequacy

**Verdict**: [Tests adequate / Tests partially adequate / Tests inadequate / No tests provided]
**Gaps**: [Specific untested scenarios, or "None"]
**Related concerns**: [Security-relevant sibling issues identified in Phase 2, or "None"]

## Results

| Phase | Result |
|---|---|
| Test adequacy | [Verdict from Phase 2] |
| clang-format | No issues / [detail if problems] |
| Pre-patch tests | N/A / Fail as expected / [detail if unexpected] |
| Post-patch tests | Pass / [detail if failures] |
| Sanitizers (UBSan+ASan) | Clean / [detail if findings] |
| Fuzzing | N/A / Clean / [detail if crashes] |
| Coverage | Adequate / [detail if gaps] |

## Timing

| Metric | Value |
|---|---|
| Wall time | [Xm Ys] |

## Issues

[Numbered list of issues to address. If none, write "None."]

## Code Quality Notes

[Only include if there are observations worth mentioning — correctness concerns, edge cases, style issues in new code. Omit this section entirely if the code looks good.]
```

After writing the report, print:
1. The path to the saved report file.
2. If the verdict is **APPROVE** and the patches are in a worktree with commits,
   suggest pushing to the exchange remote so the host can fetch them:
   ```
   The patches look good. Push to exchange so the host can pick them up:
     cd <NSS_DIR> && git push exchange <branch-name>
   ```
   Only suggest this — do not push without the user's confirmation.
3. Cleanup commands — only for **bug-number mode** where a fresh review worktree was created:

```sh
# Bug-number mode only — remove the review worktree and its build artefacts:
git -C /workspaces/nss-dev/nss worktree remove "$WORKTREE_DIR"
rm -rf "$NSS_DIST_DIR"
```

In worktree mode the user owns the worktree; do not suggest removing it.
