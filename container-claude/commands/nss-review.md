---
name: nss-review
description: Review an NSS/NSPR bug patch. Use when the user says "/nss-review BUGNUM", "review bug XXXXX", "review patch for bug", or similar. Performs full patch validation including test verification, sanitizer builds, fuzzing, and coverage analysis.
version: 1.3.0
disable-model-invocation: true
---

# NSS Bug Patch Review

Review bug: $ARGUMENTS

Follow each phase below in order. Record the outcome of every step — both pass and fail — for the final summary.

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

if git -C /workspaces/nss-dev/nss worktree list --porcelain \
     | grep -qF "worktree $WORKTREE_DIR"; then
  echo "Reusing existing worktree: $WORKTREE_DIR"
else
  echo "Creating worktree: $WORKTREE_DIR"
  mkdir -p /workspaces/nss-dev/worktrees
  git -C /workspaces/nss-dev/nss worktree add --detach "$WORKTREE_DIR"
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

Read the full diff. Identify and record:

- **Summary**: What does this patch do? What bug is it fixing?
- **Files changed**: List all modified source files with a brief note on what changed in each
- **Test files**: List any new or modified test files (paths containing `gtest`, `_test`, `tests/`)
- **Code areas touched**: Which NSS subsystems are affected? (TLS/SSL, PKI/cert, crypto, PKCS11, PKCS12, etc.)
- **Fuzz-relevant**: Are any of the changed areas covered by fuzzers in `$NSS_DIR/fuzz/targets/`? Map changed code to relevant fuzzer targets.
- **Coverage strategy**: Which gtest suites and test shell scripts are most relevant to the changed code?

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
  GTESTFILTER="$GTESTFILTER" bash ssl_gtests/ssl_gtests.sh
```
For other gtest suites, use the appropriate script under `$NSS_DIR/tests/`.

**Expected outcome**: New test cases should FAIL here (they test the bug being fixed). Record whether each test case failed as expected or unexpectedly passed.

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

# Get the list of C/C++ files changed by the patch
CHANGED=$(git diff --name-only -- '*.c' '*.cc' '*.cpp' '*.h')

# Dry-run clang-format — reports violations without modifying files
clang-format --dry-run --Werror $CHANGED 2>&1
```

If `clang-format` exits non-zero, it prints the reformatting warnings. Record any violations (file name + line range is sufficient). No `git restore` is needed since `--dry-run` does not modify files.

---

## Phase 5: Build and Test (UBSan + ASan combined)

UBSan and ASan can be enabled together in a single build. Build once, run the relevant tests once, and record results for both sanitizers.

The relevant tests are those identified in Phase 1; for ssl_gtest use a `GTESTFILTER`, for other suites use the appropriate script under `$NSS_DIR/tests/`.

**Build with both sanitizers:**
```sh
cd "$NSS_DIR"
NSS_DIST_DIR="$NSS_DIST_DIR" ./build.sh -c --ubsan --asan 2>&1 | tail -30
```
Record: build success/failure, any warnings in changed files.

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
  GTESTFILTER="$GTESTFILTER" bash ssl_gtests/ssl_gtests.sh
```

Expected: all tests pass, including any new test cases that failed in Phase 2. Record any UBSan errors (undefined behaviour reports) and ASan errors (heap/stack overflow, use-after-free, etc.) that appear in the test output.

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

Record: any crashes or timeouts found. Note the exec/s rate as a sanity check that the fuzzer is running.

---

## Phase 7: Coverage Check

Use `./mach test-coverage` for unit-test line coverage and `./mach fuzz-coverage` for fuzzer coverage. Do not attempt to pass coverage flags directly to `build.sh` — that approach does not work.

**For unit test coverage** (run relevant test suites only using `--test`):
```sh
cd "$NSS_DIR"
./mach test-coverage --test ssl_gtests
```

**For fuzz coverage** (limit to relevant fuzzer targets using `--targets`):
```sh
cd "$NSS_DIR"
./mach fuzz-coverage --targets tls-client,tls-server --max-total-time=30
```

Both commands produce an HTML report and a summary. Focus the coverage assessment on the specific files changed in the patch. Report percentage coverage and any uncovered lines in changed code that seem like they should be tested.

If coverage tools are unavailable or the build fails, note it and skip.

---

## Phase 8: Review Summary

Produce a structured review report covering all phases, followed by a worktree cleanup note:

```
## NSS Bug $ARGUMENTS — Patch Review

### Patch Summary
[1-2 sentence description of what the patch does]

### Files Changed
[List of files and brief description of changes]

### clang-format (Phase 4)
- [CLEAN / violations found in new code: ...]

### Test Verification
- Pre-patch (Phase 2): [new tests FAIL as expected / not applicable / UNEXPECTED PASS]
- Post-patch (Phase 5): [all tests PASS / failures listed]

### Sanitizer Results
- UBSan + ASan (Phase 5): [CLEAN / issues found: ...]

### Fuzzing (Phase 6)
- Fuzzers run: [list or "N/A"]
- Crashes found: [none / list]

### Coverage (Phase 7)
- Changed files coverage: [X% / not measured]
- Uncovered lines of concern: [none / list]

### Code Quality Notes
[Any observations about the code changes: correctness, style, edge cases, missing error handling, etc.]

### Verdict
[APPROVE / NEEDS WORK / NEEDS DISCUSSION]

### Recommendations
[Numbered list of any issues that should be addressed before landing]
```

After delivering the report, print the cleanup commands so the user can remove the worktree and dist when they're done:

```sh
# To remove the review worktree and its build artefacts when done:
git -C /workspaces/nss-dev/nss worktree remove "$WORKTREE_DIR"
rm -rf "$NSS_DIST_DIR"
```
