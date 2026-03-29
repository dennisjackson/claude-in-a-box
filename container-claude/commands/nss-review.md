---
name: nss-review
description: Review an NSS/NSPR bug patch. Use when the user says "/nss-review BUGNUM", "review bug XXXXX", "review patch for bug", or similar. Performs full patch validation including test verification, sanitizer builds, fuzzing, and coverage analysis.
version: 1.3.0
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

### 0a. Determine the bug number

If `$ARGUMENTS` is non-empty, use it as the bug number. Otherwise, find the latest bug folder under `/workspaces/nss-dev/bugs/` by listing subdirectories sorted by name and taking the last one. Use that folder's name as the bug number for the rest of this review.

### 0b. Set up a dedicated review worktree

Create an isolated git worktree for this review so that applying patches, building, and running tests does not touch the main checkout. The worktree is a detached HEAD at the current tip of the main tree.

```sh
BUGNUM=<bug number from 0a>
WORKTREE_DIR=/workspaces/nss-dev/worktrees/review-$BUGNUM
NSS_DIST_DIR=/workspaces/nss-dev/dist-review-$BUGNUM

# Always create the parent dir first so the nspr symlink can be placed there.
mkdir -p /workspaces/nss-dev/worktrees

if [ -d "$WORKTREE_DIR" ]; then
  echo "Reusing existing worktree: $WORKTREE_DIR"
else
  echo "Creating worktree: $WORKTREE_DIR"
  # A stale registry entry (no live directory) may exist from a previous run.
  # --force lets git overwrite it without touching any other active worktrees.
  git -C /workspaces/nss-dev/nss worktree add --detach "$WORKTREE_DIR" \
    || git -C /workspaces/nss-dev/nss worktree add --force --detach "$WORKTREE_DIR"
fi

NSS_DIR=$WORKTREE_DIR

# Ensure the worktree can find NSPR (build.sh resolves $cwd/../nspr)
ln -sfn /workspaces/nss-dev/nspr /workspaces/nss-dev/worktrees/nspr

echo "NSS_DIR:      $NSS_DIR"
echo "NSS_DIST_DIR: $NSS_DIST_DIR"
```

All subsequent phases use `$NSS_DIR` and `$NSS_DIST_DIR`. The main checkout at `/workspaces/nss-dev/nss` and its dist at `/workspaces/nss-dev/dist` are never touched.

### 0c. Find the patch

Search for the patch file in `/workspaces/nss-dev/bugs/<BUGNUM>/attachments/` — list all `.diff` and `.patch` files there. If multiple exist, review all of them.

If no diff is found, stop and ask the user where the patch file is located.

---

## Phase 1: Patch Analysis

Read the full diff. Internally note the files changed, subsystems affected, relevant fuzzers and test suites — you need these to drive later phases. Only output a 1-2 sentence summary of what the patch does. Save detailed file lists for the final report.

---

## Phase 2: Pre-Patch Test Verification (Tests Must Fail)

This phase verifies that any new test cases in the patch actually test the bug being fixed.

**Only run this phase if the patch adds new gtest test cases.**

2a. Check whether the patches are already applied to the working tree:
```sh
cd "$NSS_DIR"
git status
```

**If patches are NOT yet applied** (clean working tree): proceed to step 2b — build the clean baseline directly.

**If patches ARE already applied** (working tree is dirty): stash all changes, then apply only the test-addition patch(es) — i.e. the patch file(s) that only add new test cases without modifying production code. This lets you run the new tests against the unfixed code.
```sh
git stash
git apply /path/to/test-only-patch.diff
```
Then proceed to step 2b.

2b. Build NSS (standard build):
```sh
cd "$NSS_DIR"
NSS_DIST_DIR="$NSS_DIST_DIR" ./build.sh 2>&1 | tail -20
```

2c. Extract new test names programmatically from the patch diff, then run them in a single invocation:
```sh
# Extract new TEST/TEST_F/TEST_P names from the patch as a GTESTFILTER
GTESTFILTER=$(grep -E '^\+\s*TEST(_F|_P)?\(' /path/to/patch.diff \
  | sed -E 's/.*TEST(_F|_P)?\(([^,]+),\s*([^)]+)\).*/\2.\3/' \
  | paste -sd ':')
echo "GTESTFILTER=$GTESTFILTER"

cd "$NSS_DIR/tests"
HOST=localhost DOMSUF=localdomain USE_64=1 DIST="$NSS_DIST_DIR" \
  GTESTFILTER="$GTESTFILTER" bash ssl_gtests/ssl_gtests.sh 2>&1 \
  | tee /tmp/pre-patch-run.log | tail -15
# Show any gtest-level failures in one pass — no need to re-run
grep -E "^\[  FAILED  \]|: Failure$|Expected|Which is:" /tmp/pre-patch-run.log | head -30
```
For other gtest suites, use the appropriate script under `$NSS_DIR/tests/`.

**Expected outcome**: New test cases should FAIL here (they test the bug being fixed). Only report detail if tests unexpectedly pass. If they fail as expected, say "New tests fail on unfixed code as expected."

---

## Phase 3: Apply the Patch

**If the working tree is clean** (patches not yet applied, or just stashed in Phase 2):
```sh
cd "$NSS_DIR"
git apply --check /path/to/patch   # dry run first
git apply /path/to/patch
```

**If Phase 2 stashed the original changes**: restore the full set of patches via `git stash pop` instead of re-applying manually.

**If there are multiple patch files**: apply them in dependency order (fix patch first, then additional test patches, or combined if independent).

If `git apply` fails, try `patch -p1 < /path/to/patch`. Record any apply errors or conflicts.

---

## Phase 4: clang-format Check

Check that all modified C/C++ source files in the patch conform to NSS formatting rules. Run `clang-format --dry-run --Werror` on only the files changed by the patch. This avoids modifying the working tree and cleanly separates patch violations from pre-existing ones.

```sh
cd "$NSS_DIR"

# Dry-run clang-format per file — avoids path issues with word-split lists
git diff --name-only -- '*.c' '*.cc' '*.cpp' '*.h' | while read -r f; do
  clang-format --dry-run --Werror "$f" 2>&1
done
```

If any file exits non-zero, clang-format prints the reformatting warnings. Record violations (file name + line range is sufficient) and note whether they are in newly added lines or pre-existing. No `git restore` is needed since `--dry-run` does not modify files.

---

## Phase 5: Build and Test (UBSan + ASan combined)

UBSan and ASan can be enabled together in a single build. Build once, run the relevant tests once, and record results for both sanitizers.

The relevant tests are those identified in Phase 1; for ssl_gtest use a `GTESTFILTER`, for other suites use the appropriate script under `$NSS_DIR/tests/`.

**Build with both sanitizers:**
```sh
cd "$NSS_DIR"
NSS_DIST_DIR="$NSS_DIST_DIR" ./build.sh -c --ubsan --asan 2>&1 | tail -30
```
If the build succeeds cleanly, say "Build OK." Only show output on failure or warnings in changed files.

**Run relevant tests** (reuse the `GTESTFILTER` extracted in Phase 2, or extract it now if Phase 2 was skipped):
```sh
# Extract GTESTFILTER if not already set from Phase 2
if [ -z "$GTESTFILTER" ]; then
  GTESTFILTER=$(grep -E '^\+\s*TEST(_F|_P)?\(' /path/to/patch.diff \
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

## Phase 6: Fuzzing (Brief)

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

## Phase 7: Coverage Check

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
# Combine all patch files into one diff
cat /workspaces/nss-dev/bugs/$BUGNUM/attachments/*.diff > /tmp/review-$BUGNUM.diff

COVERAGE_REPORT=/workspaces/nss-dev/bugs/$BUGNUM/coverage-report.html
diff-cover "$LCOV_FILE" \
  --diff-file /tmp/review-$BUGNUM.diff \
  --html-report "$COVERAGE_REPORT" \
  2>&1
echo "Coverage report: $COVERAGE_REPORT"
```

diff-cover prints a per-file summary of what percentage of lines added/changed by the patch are covered. If coverage looks adequate for the changed files, say "Coverage adequate for changed files." Only call out specific uncovered lines if they look like they should be tested.

If `diff-cover` is not installed or the build fails, say "Skipped — [reason]" and move on.

---

## Phase 8: Review Summary

Produce a compact review report. For phases with no issues, use a single "No issues" line — do not repeat the details. Only expand on phases that found real problems.

**Record the end time:**
```sh
date -u +%s
```
Calculate elapsed wall-clock time from the start time recorded before Phase 0.

Write the report to `/workspaces/nss-dev/bugs/<BUGNUM>/review.md` so it persists alongside the bug data.

Report format:

```
# NSS Bug <BUGNUM> — Patch Review

**Patch**: [1-2 sentence description]
**Files**: [list of changed files]
**Verdict**: [APPROVE / NEEDS WORK / NEEDS DISCUSSION]

## Results

| Phase | Result |
|---|---|
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
2. The cleanup commands:

```sh
# To remove the review worktree and its build artefacts when done:
git -C /workspaces/nss-dev/nss worktree remove "$WORKTREE_DIR"
rm -rf "$NSS_DIST_DIR"
```
