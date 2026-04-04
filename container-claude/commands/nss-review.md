---
name: nss-review
description: Review an NSS/NSPR bug patch. Use when the user says "/nss-review BUGNUM", "review bug XXXXX", "review patch for bug", "review patches in worktree <name>", or similar. Performs full patch validation including test verification, sanitizer builds, fuzzing, and coverage analysis.
version: 2.0.0
---

# NSS Bug Patch Review

Review bug: $ARGUMENTS

Follow each phase below in order. Be terse: if a phase completes without issues, just record "No issues" and move on. Only provide detail when something fails, looks suspicious, or needs the user's attention.

**Report requirement**: You MUST write the report file when you complete the final phase. If the user continues the conversation and subsequent discussion reveals new information — corrections, additional findings, revised verdict, missed issues — update the report file to reflect the current best understanding. The report should always represent the most accurate and complete picture available.

**Skepticism principle**: Do not take bug descriptions, commit messages, comments, or patch rationale at face value. These are **claims** — they may be wrong, incomplete, or misleading (whether through honest error or adversarial intent). Your job is to independently verify that the patch is correct by reading the code, not by trusting the author's narrative. Specifically:
- If the bug report says "X is the root cause," verify by reading the code that X is actually the root cause.
- If the commit message says "this fixes the issue by doing Y," verify that Y actually addresses the problem and does not merely suppress a symptom.
- If a comment in the patch says "this cannot happen" or "this is always non-null," treat it as a hypothesis to check, not a fact.
- If the patch changes something you don't fully understand, read the surrounding code until you do. Do not assume the author understood it either.

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
  git -C /workspaces/nss-dev/nss worktree add --detach "$WORKTREE_DIR"
  # If this fails, do NOT use --force blindly — it may reuse a worktree with
  # a different HEAD than expected. Diagnose the error first (e.g., stale
  # worktree entry: run `git worktree prune` then retry).
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
BUG_DIR=$(ls -d /workspaces/nss-dev/bugs/*${BUGNUM}*/ 2>/dev/null | head -1)
if [ -n "$BUG_DIR" ]; then
  echo "Bug context available at $BUG_DIR"
  ls "$BUG_DIR"
else
  echo "No bugs/ folder found for $BUGNUM — working from worktree commits only"
fi
```

**Bug-number mode** — find patch files in the attachments folder:
```sh
BUG_DIR=$(ls -d /workspaces/nss-dev/bugs/*${BUGNUM}*/ 2>/dev/null | head -1)
if [ -z "$BUG_DIR" ]; then
  echo "ERROR: no bug folder found for $BUGNUM"
  exit 1
fi

ATTACH_DIR=$BUG_DIR/input/attachments
PATCHES=$(ls "$ATTACH_DIR"/*.diff "$ATTACH_DIR"/*.patch 2>/dev/null)
if [ -z "$PATCHES" ]; then
  echo "ERROR: no .diff or .patch files found in $ATTACH_DIR"
  exit 1
fi
echo "$PATCHES"

# If there is a single patch file, use it directly. If there are multiple,
# list them and let the reviewer inspect each individually — blindly
# concatenating patches can produce a malformed diff if they overlap.
PATCH_COUNT=$(echo "$PATCHES" | wc -l)
if [ "$PATCH_COUNT" -eq 1 ]; then
  PATCH_FILE=$PATCHES
else
  echo "WARNING: $PATCH_COUNT patch files found — review each for overlap before combining."
  echo "Concatenating in filesystem order. Verify the combined diff is well-formed."
  PATCH_FILE=/tmp/review-$BUGNUM.diff
  cat $PATCHES > "$PATCH_FILE"
fi
echo "Patch file: $PATCH_FILE ($PATCH_COUNT file(s))"
```

---

## Phase 1: Patch Analysis

### 1a. Read the patch

Read the full diff at `$PATCH_FILE`. Internally note the files changed, subsystems affected, and relevant test suites — you need these to drive later phases. Save detailed file lists for the final report.

Note which subsystems are touched (e.g., TLS, certificates, PKCS, hashing, DTLS) — you will use this in Phase 8 to select fuzz targets from the actual inventory. Do not pre-judge which fuzzers are relevant without listing them first.

**Determine the test suite(s)** for the affected subsystem(s). Match changed files to the correct gtest script:
- `lib/ssl/` → `ssl_gtests/ssl_gtests.sh`
- `lib/pk11wrap/` → `pk11_gtests/pk11_gtests.sh`
- `lib/certdb/` → `certdb_gtests/certdb_gtests.sh`
- `lib/mozpkix/` → `mozpkix_gtests/mozpkix_gtests.sh`
- `lib/util/` (DER/encoding) → `der_gtests/der_gtests.sh`
- `lib/freebl/` → `freebl_gtests/freebl_gtests.sh`
- `lib/softoken/` → `softoken_gtests/softoken_gtests.sh`
- `lib/smime/` → `smime_gtests/smime_gtests.sh`
- Check `ls $NSS_DIR/tests/` for additional suites if the above don't match.

Set `GTEST_SCRIPT` to the matching script path (e.g., `ssl_gtests/ssl_gtests.sh`). If tests span multiple suites, note all of them. All subsequent phases use `$GTEST_SCRIPT` to run the correct suite.

Also determine the `./mach test-coverage --test` argument. This is typically the suite name without the `_gtests` suffix and `_sh` suffix of the script — e.g., `ssl_gtests` for `ssl_gtests/ssl_gtests.sh`. Set `COVERAGE_SUITE` accordingly.

If `$BUG_DIR` was found and contains `input/bug.md` or similar summary files, read them. Treat as **context**, not **truth** — note any claims they make that you will need to verify.

### 1b. Independently verify the root cause

Do not rely on the bug report or commit message to tell you what the bug is. Read the actual pre-patch code at the defect site and answer for yourself:
- What does this code do?
- What invariants does it assume? Are those assumptions valid?
- What inputs or states violate those assumptions?
- Does your understanding of the bug match what the patch author claims? If not, note the discrepancy — it may indicate the patch fixes the wrong thing.

### 1c. Verify the fix is correct

Read the patched code and determine whether the fix **actually resolves the root cause** you identified in 1b (not the root cause the author claims). Check for:
- **Symptom suppression**: Does the fix just prevent the crash/error without addressing the underlying logic flaw? (e.g., adding a NULL check that prevents a crash but leaves the code in a corrupt state)
- **Incomplete fix**: Does the fix handle the specific trigger from the bug report but miss other inputs that trigger the same defect? (e.g., bounds-checking one field but not a sibling field parsed by the same code)
- **Introduced defects**: Does the fix introduce new problems? (e.g., an early return that skips necessary cleanup, a bounds check that uses `<=` when it should use `<`, a signed/unsigned comparison that can still underflow)
- **Scope creep**: Does the patch include changes unrelated to the bug fix that might introduce risk?

Output a 1-2 sentence summary of what the patch does, plus a note if your understanding of the bug diverges from the author's.

### 1d. Patch quality: simplicity, minimality, and clarity

Evaluate the patch against these criteria:

**Minimality** — Does the patch contain only what is necessary to fix the bug? Flag:
- Unrelated refactoring, style changes, or whitespace cleanup in lines not affected by the fix
- "While I'm here" additions — extra validation, logging, or hardening beyond what the bug requires
- Dead code removal or variable renames that are not needed for the fix

**Simplicity** — Is the approach straightforward? Flag:
- Overly clever solutions when a simpler one exists (e.g., a complex state machine change when a bounds check suffices)
- Unnecessary indirection or abstraction added for a single use site

**Clarity** — Is the code self-explanatory? Flag:
- Verbose or explanatory comments that restate what the code already says (e.g., `/* check if length is zero */ if (len == 0)`)
- Bug-specific comments that belong in the commit message, not in code (e.g., `/* Bug 1234567: this was missing */` or `/* Fixed: the length was not checked */`)
- Comments that explain "why the old code was wrong" — the commit message is the right place for that context

**Commit messages** — Check commit messages against NSS convention (`Bug NNNNNN - Short imperative description r=#nss-reviewers`). Flag:
- Overly verbose first lines (should be under ~72 characters)
- Multi-paragraph commit bodies that repeat what the diff shows — the body should explain *why*, not *what*, and only when the diff is not self-explanatory
- Attribution trailers (Co-Authored-By, etc.) which NSS does not use

Record any issues for the final report under a **Patch Quality** subsection.

### 1e. Platform portability

NSS builds and runs on Linux, macOS, Windows, FreeBSD, and others, on both 32-bit and 64-bit architectures (x86, x64, ARM, AArch64). Both the fix and the tests must be portable. Review all changed files for:

**Fix code:**
- **Integer width assumptions**: `int`, `long`, and pointer sizes vary across platforms. `long` is 32-bit on Windows LLP64 even on 64-bit builds. Prefer `PRUint32`, `PRInt32`, `size_t`, `PRUintn` or explicit fixed-width types over bare `int`/`long` for values that could exceed 32 bits or where width matters. Flag any arithmetic that is only correct on LP64 (where `long` is 64-bit).
- **Signed/unsigned mismatch**: Implicit conversions between signed and unsigned types may behave differently when widths change across platforms.
- **Pointer-size assumptions**: Code that casts between pointers and integers, or assumes `sizeof(void*) == 8`.
- **Platform-specific APIs in library code**: POSIX-only calls (`mmap`, `unistd.h` functions, etc.) in code that should be cross-platform. NSS library code uses NSPR abstractions (`PR_*`) for portability.

**Test code:**
- **OS-specific headers**: `<sys/mman.h>`, `<unistd.h>`, `<windows.h>`, etc. without `#ifdef` guards. Tests using POSIX-only APIs (e.g., `mmap`, `fork`) need `#if !defined(_WIN32)` or equivalent guards.
- **Architecture-specific assumptions**: Tests that assume 64-bit address space (e.g., allocating >2 GB), 64-bit `size_t`, specific endianness, or specific alignment. Guard with `sizeof(void*)` checks or `GTEST_SKIP()` on unsupported platforms.
- **Resource assumptions**: Tests requiring large amounts of memory (>1 GB) should be guarded so they skip gracefully on constrained environments rather than crashing.

Flag any portability issues for the final report under **Issues**. If the fix code has portability problems, this is a correctness issue. If only the test has portability problems, note it as a quality issue that should be fixed before landing.

---

## Phase 2: Test Adequacy Analysis

This phase determines whether the patch's tests actually validate the core issue. Perform this analysis before running any tests so the results of later phases can be evaluated against it.

**2a. Identify the core issue being fixed.**

Read the bug summary (`$BUG_DIR/input/bug.md` if available), the patch diff, and any commit messages. Answer concisely:
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

**2d. Test quality: suitability, redundancy, and abstraction level.**

Evaluate the tests themselves for quality, independent of coverage:

**Abstraction level** — Tests should prefer exercising public APIs and high-level functions over reaching into internal implementation details. Flag:
- Tests that call internal/static helper functions when the same behavior could be validated through a public API (e.g., `PK11_*`, `SEC_*`, `CERT_*`, `SSL_*`, or the gtest connection harness)
- Tests that depend on internal struct layout, private constants, or implementation-specific state that could change without affecting correctness
- Exception: if the bug is specifically in an internal function with no observable effect at the public API level, a targeted internal test is acceptable — note this when it applies

**Redundancy** — Tests should not duplicate existing coverage. Flag:
- New tests that are substantially identical to existing tests in the same suite (same setup, same assertions, different only in name)
- Multiple test cases that exercise the same code path with trivially different inputs when one case suffices
- Tests that re-verify behavior already covered by existing tests unless the patch changes that behavior

**Suitability** — Tests should be appropriate for what they are validating. Flag:
- Tests that assert on incidental behavior rather than the specific fix (e.g., checking the full error string instead of the error code)
- Verbose test code with excessive comments explaining the test — the test name and structure should make the intent clear

Produce a short verdict:
- **Tests adequate** — the critical path and key variants are tested.
- **Tests partially adequate** — the critical path is tested but [specific gaps].
- **Tests inadequate** — the tests do not exercise the actual trigger condition, or no tests are provided for a security-relevant fix.
- **No tests provided** — note whether tests are expected (security fix → tests strongly expected; trivial refactor → may be acceptable).

Record this verdict, the quality assessment, and any gaps for the final report. Do not block the review on this — it is an assessment, not a gate.

---

## Phase 3: Falsification — Try to Break the Patch

This phase actively tries to disprove the patch's correctness. The goal is to construct specific, testable hypotheses about how the patch could fail and then test them. A patch that survives honest attempts at falsification deserves more confidence than one that was only tested on the happy path.

### 3a. Generate falsification hypotheses

Based on your independent analysis in Phase 1, construct **3-7 testable hypotheses** about how the patch could be wrong. Each hypothesis should be specific enough to test by reading code, writing a test, or constructing an input. Categories to consider:

**Boundary conditions:**
- Does the fix handle the minimum value (0, empty, NULL)?
- Does the fix handle the maximum value (UINT32_MAX, buffer-sized, etc.)?
- Does the fix handle off-by-one at the boundary?

**Alternative triggers:**
- Can the same bug be reached through a different caller or protocol path that the fix does not cover?
- If the fix is in TLS, does the same issue exist in DTLS (or vice versa)?
- If the fix is in one handshake message handler, do sibling handlers have the same pattern?

**Interaction and ordering:**
- Can the vulnerable code be reached by sending messages in an unexpected order?
- Does the fix depend on state that could be different under resumption, 0-RTT, or HRR?
- Could a race condition bypass the fix?

**Fix correctness:**
- If the fix adds a bounds check: is the bound itself trustworthy, or is it also attacker-controlled?
- If the fix adds an error return: do all callers handle the new error code? Could the error propagation leave state half-modified?
- If the fix changes control flow: does the new path skip cleanup, unlocking, or other side effects that the old path performed?

**Regression:**
- Does the fix break valid inputs that previously worked? (e.g., an overly strict check that rejects legal certificates or extensions)

Format each hypothesis as: "H[N]: [claim that, if true, means the patch is wrong]. Test: [how to check]."

### 3b. Test the hypotheses

For each hypothesis, attempt to confirm or refute it:

- **Code reading**: Trace the relevant code paths. Follow callers, check error handling, verify bounds. This is sufficient for most hypotheses.
- **grep / weggli**: Search for alternative callers, sibling handlers, or the same pattern elsewhere:
  ```sh
  cd "$NSS_DIR"
  grep -rn "function_name" lib/ --include='*.c'
  weggli '<pattern>' lib/
  ```
- **Write a test** (if practical and the hypothesis is high-value): Construct a targeted gtest or input that exercises the hypothesized failure. Build and run it:
  ```sh
  cd "$NSS_DIR"
  NSS_DIST_DIR="$NSS_DIST_DIR" ./build.sh 2>&1 | tail -20
  cd tests
  HOST=localhost DOMSUF=localdomain USE_64=1 DIST="$NSS_DIST_DIR" \
    GTESTFILTER="<TestSuite>.<TestName>" bash <suite>_gtests/<suite>_gtests.sh 2>&1 \
    | tee /tmp/falsify-run.log | tail -15
  ```
- **Sanitizer check**: If a hypothesis involves memory safety, the UBSan/ASan build in Phase 7 will also test it — note this and defer if appropriate.

### 3c. Record results

For each hypothesis, record:
- **H[N]**: The hypothesis
- **Result**: Refuted (the patch handles this correctly — state why) / **Confirmed** (the patch has this flaw) / **Inconclusive** (could not determine — explain why and flag for human review)
- **Evidence**: 1-2 sentences describing what you found (file:line references, test outcome, etc.)

If any hypothesis is **Confirmed**, this is a review finding — it goes into the Issues section of the final report and influences the verdict. If a hypothesis is **Inconclusive** on a security-relevant question, flag it as needing human review.

---

## Phase 4: Pre-Patch Test Verification (Tests Must Fail)

This phase verifies that any new test cases in the patch actually test the bug being fixed.

**Only run this phase if the patch adds new gtest test cases.**

4a. Determine the state of the working tree:

**Worktree mode** — patches are already committed; the working tree should be clean.
To test unfixed code, temporarily check out the base commit, then restore:
```sh
PATCHED_HEAD=$(git -C "$NSS_DIR" rev-parse HEAD)
git -C "$NSS_DIR" checkout "$BASE"
# → proceed to step 4b
# After testing, restore with: git -C "$NSS_DIR" checkout $PATCHED_HEAD
```

**Bug-number mode** — check whether patches are already applied:
```sh
git -C "$NSS_DIR" status
```
- **Clean working tree**: proceed to step 4b directly.
- **Dirty working tree** (patches already applied): stash all changes, then apply only the test-addition patch(es) — i.e. the patch file(s) that only add new test cases without modifying production code:
  ```sh
  git -C "$NSS_DIR" stash
  git -C "$NSS_DIR" apply /path/to/test-only-patch.diff
  ```

4b. Build NSS (standard build):
```sh
cd "$NSS_DIR"
NSS_DIST_DIR="$NSS_DIST_DIR" ./build.sh 2>&1 | tail -20
```

4c. Extract new test names programmatically from the patch diff, then run them in a single invocation:
```sh
# Extract test names from TEST, TEST_F, and TEST_P macros
GTESTFILTER=$(grep -E '^\+\s*TEST(_F|_P)?\(' "$PATCH_FILE" \
  | sed -E 's/.*TEST(_F|_P)?\(([^,]+),\s*([^)]+)\).*/\2.\3/' \
  | paste -sd ':')

# Fallback: if no TEST macros found (e.g., tests defined via other macros or
# INSTANTIATE_TEST_SUITE_P), search for new test class/function names more broadly
if [ -z "$GTESTFILTER" ]; then
  GTESTFILTER=$(grep -E '^\+.*(INSTANTIATE_TEST_SUITE_P|TYPED_TEST)\(' "$PATCH_FILE" \
    | sed -E 's/.*\(([^,]+),\s*([^)]+)\).*/\2.\1*/' \
    | paste -sd ':')
fi

# If still empty, warn — manual GTESTFILTER may be needed
if [ -z "$GTESTFILTER" ]; then
  echo "WARNING: Could not extract test names from patch. Set GTESTFILTER manually."
fi

echo "GTESTFILTER=$GTESTFILTER"

cd "$NSS_DIR/tests"
HOST=localhost DOMSUF=localdomain USE_64=1 DIST="$NSS_DIST_DIR" \
  GTESTFILTER="$GTESTFILTER" bash $GTEST_SCRIPT 2>&1 \
  | tee /tmp/pre-patch-run.log | tail -15
grep -E "^\[  FAILED  \]|: Failure$|Expected|Which is:" /tmp/pre-patch-run.log | head -30
```

After testing, restore the patched state:
- **Worktree mode**: `git -C "$NSS_DIR" checkout $PATCHED_HEAD`
- **Bug-number mode** (stashed): `git -C "$NSS_DIR" stash pop`

**Expected outcome**: New test cases should FAIL here (they test the bug being fixed). Only report detail if tests unexpectedly pass. If they fail as expected, say "New tests fail on unfixed code as expected."

---

## Phase 5: Apply the Patch

**Worktree mode** — patches are already committed; nothing to apply. Confirm:
```sh
git -C "$NSS_DIR" log --oneline "$BASE"..HEAD
```
Record the commit summary and move on.

**Bug-number mode:**

If the working tree is clean (patches not yet applied, or just restored from stash in Phase 4):
```sh
cd "$NSS_DIR"
git apply --check "$PATCH_FILE"   # dry run first
git apply "$PATCH_FILE"
```

If Phase 4 stashed the original changes: restore the full set of patches via `git stash pop` instead of re-applying manually.

If there are multiple patch files in bug-number mode: apply them in dependency order (fix patch first, then additional test patches, or combined if independent).

If `git apply` fails, try `patch -p1 < "$PATCH_FILE"`. Record any apply errors or conflicts.

---

## Phase 6: clang-format Check

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

## Phase 7: Build and Test (UBSan + ASan combined)

UBSan and ASan can be enabled together in a single build. Build once, run the relevant tests once, and record results for both sanitizers.

The relevant tests are those identified in Phase 1; for ssl_gtest use a `GTESTFILTER`, for other suites use the appropriate script under `$NSS_DIR/tests/`.

**Build with both sanitizers:**
```sh
cd "$NSS_DIR"
NSS_DIST_DIR="$NSS_DIST_DIR" ./build.sh -c --ubsan --asan 2>&1 | tee /tmp/sanitizer-build.log | tail -30
if [ ${PIPESTATUS[0]} -ne 0 ]; then
  echo "BUILD FAILED — see /tmp/sanitizer-build.log"
fi
```
If the build fails, diagnose the error before proceeding — running tests against stale binaries produces misleading results. If the build succeeds cleanly, say "Build OK." Only show output on failure or warnings in changed files.

**Run relevant tests** (reuse the `GTESTFILTER` extracted in Phase 4, or extract it now if Phase 4 was skipped):
```sh
if [ -z "$GTESTFILTER" ]; then
  GTESTFILTER=$(grep -E '^\+\s*TEST(_F|_P)?\(' "$PATCH_FILE" \
    | sed -E 's/.*TEST(_F|_P)?\(([^,]+),\s*([^)]+)\).*/\2.\3/' \
    | paste -sd ':')
fi

cd "$NSS_DIR/tests"
HOST=localhost DOMSUF=localdomain USE_64=1 DIST="$NSS_DIST_DIR" \
  GTESTFILTER="$GTESTFILTER" bash $GTEST_SCRIPT 2>&1 \
  | tee /tmp/post-patch-run.log | tail -15
grep -E "^\[  FAILED  \]|: Failure$|Expected|Which is:" /tmp/post-patch-run.log | head -30
```

Expected: all tests pass. If they do and no sanitizer errors appear, say "All tests pass. No sanitizer issues." Only report detail on failures or sanitizer findings.

---

## Phase 8: Fuzzing (Brief)

**Target identification**: Do not guess which fuzzers are relevant based on examples or assumptions. Build with fuzzing support first, then list the actual available targets and select those that exercise code paths touched by the patch. Skip this phase only if, after listing targets, none are relevant.

**Build with fuzzing support.** TLS/DTLS client and server fuzzers require `--fuzz=tls` (Totally Lacking Security mode); all other targets use `--fuzz`. If unsure which you need, build with `--fuzz=tls` (it includes all targets):
```sh
cd "$NSS_DIR"
NSS_DIST_DIR="$NSS_DIST_DIR" ./build.sh --fuzz=tls --disable-tests 2>&1 | tail -20
```

**List available fuzz targets** — this is mandatory, not optional:
```sh
ls "$NSS_DIST_DIR/Debug/bin/nssfuzz-"* | sed 's/.*nssfuzz-//'
```
Review the full list and select targets that exercise subsystems touched by the patch. The target names generally correspond to the input format or protocol they fuzz (e.g., `cert-`, `pkcs8-`, `tls-`, `dtls-`, `hash-`, etc.). Match targets to the patch's affected subsystem, not to a memorized example list.

**Run each relevant target** for 30 seconds:
```sh
TARGET=<selected-target>
"$NSS_DIST_DIR/Debug/bin/nssfuzz-$TARGET" \
  -max_total_time=30 -artifact_prefix=/tmp/fuzz-$TARGET- 2>&1 | tail -10
```

If no crashes are found, say "No crashes (Xk exec/s)." Only report detail on crashes or anomalies.

---

## Phase 9: Coverage Check

Use `./mach test-coverage` for unit-test line coverage. Do not attempt to pass coverage flags directly to `build.sh` — that approach does not work.

**Run coverage and capture the LCOV path.** Use the `$COVERAGE_SUITE` determined in Phase 1a:
```sh
cd "$NSS_DIR"
./mach test-coverage --test $COVERAGE_SUITE 2>&1 | tee /tmp/coverage-run.log | tail -10
LCOV_FILE=$(grep "Coverage LCOV data:" /tmp/coverage-run.log | awk '{print $NF}')
echo "LCOV: $LCOV_FILE"
```

**Use diff-cover to focus on lines changed by the patch:**
```sh
# Use $BUG_DIR if already resolved, otherwise create under the standard path
if [ -z "$BUG_DIR" ]; then
  BUG_DIR=$(ls -d /workspaces/nss-dev/bugs/*${BUGNUM}*/ 2>/dev/null | head -1)
  : ${BUG_DIR:=/workspaces/nss-dev/bugs/$BUGNUM}
fi
REPORTS_DIR=$BUG_DIR/reports
mkdir -p "$REPORTS_DIR"
COVERAGE_REPORT=$REPORTS_DIR/coverage-report.html
diff-cover "$LCOV_FILE" \
  --diff-file "$PATCH_FILE" \
  --html-report "$COVERAGE_REPORT" \
  2>&1
echo "Coverage report: $COVERAGE_REPORT"
```

diff-cover prints a per-file summary of what percentage of lines added/changed by the patch are covered. If coverage looks adequate for the changed files, say "Coverage adequate for changed files." Only call out specific uncovered lines if they look like they should be tested.

If `diff-cover` is not installed or the build fails, say "Skipped — [reason]" and move on.

---

## Phase 10: Review Summary

Produce a compact review report. For phases with no issues, use a single "No issues" line — do not repeat the details. Only expand on phases that found real problems.

**Record the end time:**
```sh
date -u +%s
```
Calculate elapsed wall-clock time from the start time recorded before Phase 0.

Write the report to `$REPORTS_DIR/review.md`. Create the directory if it does not exist:
```sh
if [ -z "$BUG_DIR" ]; then
  BUG_DIR=$(ls -d /workspaces/nss-dev/bugs/*${BUGNUM}*/ 2>/dev/null | head -1)
  : ${BUG_DIR:=/workspaces/nss-dev/bugs/$BUGNUM}
fi
REPORTS_DIR=$BUG_DIR/reports
mkdir -p "$REPORTS_DIR"
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

## Patch Quality

**Minimality**: [Clean / issues noted]
**Clarity**: [Clean / issues noted]
**Commit messages**: [OK / issues noted]

## Test Adequacy

**Verdict**: [Tests adequate / Tests partially adequate / Tests inadequate / No tests provided]
**Gaps**: [Specific untested scenarios, or "None"]
**Quality**: [Abstraction level, redundancy, or suitability issues, or "No issues"]
**Related concerns**: [Security-relevant sibling issues identified in Phase 2, or "None"]

## Falsification

[For each hypothesis tested in Phase 3, one line:]

| # | Hypothesis | Result | Evidence |
|---|---|---|---|
| H1 | [claim] | Refuted / **Confirmed** / Inconclusive | [brief evidence] |
| H2 | ... | ... | ... |

**Confirmed findings**: [count — these are patch flaws and appear in Issues below]
**Inconclusive**: [count — flagged for human review]

## Results

| Phase | Result |
|---|---|
| Patch quality | Clean / [detail if issues] |
| Platform portability | Clean / [detail if issues — list affected platforms] |
| Test adequacy | [Verdict from Phase 2] |
| Falsification | [N hypotheses tested: N refuted, N confirmed, N inconclusive] |
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

**Update the bug log.** Append a one-line verdict to `$BUG_DIR/LOG.md`:
```sh
NOW=$(date -u +"%Y-%m-%d %H:%M UTC")
LOG_FILE="$BUG_DIR/LOG.md"
if [ ! -f "$LOG_FILE" ]; then
  printf "# Log: Bug %s\n\n" "$BUGNUM" > "$LOG_FILE"
fi
# Verdict: terse one-line summary — review verdict and key finding
echo "- $NOW — /nss-review: <APPROVE|NEEDS WORK|NEEDS DISCUSSION> — <one-line summary>" >> "$LOG_FILE"
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
