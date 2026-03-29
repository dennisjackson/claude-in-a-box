---
name: nss-review
description: Review an NSS/NSPR bug patch. Use when the user says "/nss-review BUGNUM", "review bug XXXXX", "review patch for bug", or similar. Performs full patch validation including test verification, sanitizer builds, fuzzing, and coverage analysis.
version: 1.0.0
disable-model-invocation: true
---

# NSS Bug Patch Review

Review bug: $ARGUMENTS

Follow each phase below in order. Record the outcome of every step — both pass and fail — for the final summary.

---

## Phase 0: Locate the Diff

**Determine the bug number.** If `$ARGUMENTS` is empty, find the latest bug folder under `/workspaces/nss-dev/bugs/` by listing subdirectories sorted by name and taking the last one. Use that folder's name as the bug number for the rest of this review.

Search for the patch file. Check these locations in order:
1. `/workspaces/nss-dev/bugs/<BUGNUM>/attachments/` — list all `.diff` and `.patch` files here; if multiple exist, review all of them
2. `/tmp/bug<BUGNUM>.diff`, `/tmp/bug-<BUGNUM>.diff`, `/tmp/bug<BUGNUM>.patch`
3. `~/Downloads/bug<BUGNUM>.diff`, `~/Downloads/bug<BUGNUM>.patch`
4. Any `.diff` or `.patch` file in `/tmp/` or `~/Downloads/` whose name contains `<BUGNUM>`
5. The current working directory for any `.diff` or `.patch` file

If no diff is found, stop and ask the user where the patch file is located.

---

## Phase 1: Patch Analysis

Read the full diff. Identify and record:

- **Summary**: What does this patch do? What bug is it fixing?
- **Files changed**: List all modified source files with a brief note on what changed in each
- **Test files**: List any new or modified test files (paths containing `gtest`, `_test`, `tests/`)
- **Code areas touched**: Which NSS subsystems are affected? (TLS/SSL, PKI/cert, crypto, PKCS11, PKCS12, etc.)
- **Fuzz-relevant**: Are any of the changed areas covered by fuzzers in `nss/fuzz/targets/`? Map changed code to relevant fuzzer targets.
- **Coverage strategy**: Which gtest suites and test shell scripts are most relevant to the changed code?

---

## Phase 2: Pre-Patch Test Verification (Tests Must Fail)

This phase verifies that any new test cases in the patch actually test the bug being fixed.

**Only run this phase if the patch adds new gtest test cases.**

2a. Ensure the repo is on a clean baseline (no patch applied):
```sh
cd /workspaces/nss-dev/nss
git stash list   # just to check state; do not discard anything
git status
```

2b. Build NSS (standard build):
```sh
cd /workspaces/nss-dev/nss
./build.sh 2>&1 | tail -20
```

2c. For each new gtest test case identified in Phase 1, run it using the appropriate test script with `GTESTFILTER`. Use the pattern from CLAUDE.md — for ssl_gtest:
```sh
cd /workspaces/nss-dev/nss/tests
HOST=localhost DOMSUF=localdomain USE_64=1 DIST=/workspaces/nss-dev/dist \
  GTESTFILTER="TestSuiteName.TestCaseName" bash ssl_gtests/ssl_gtests.sh
```
For other gtest suites, use the appropriate script under `nss/tests/`.

**Expected outcome**: New test cases should FAIL here (they test the bug being fixed). Record whether each test case failed as expected or unexpectedly passed.

---

## Phase 3: Apply the Patch

```sh
cd /workspaces/nss-dev/nss
git apply --check /path/to/patch   # dry run first
git apply /path/to/patch
```

If `git apply` fails, try `patch -p1 < /path/to/patch`. Record any apply errors or conflicts.

---

## Phase 4: clang-format Check

Check that all modified C/C++ source files in the patch conform to NSS formatting rules. Run the project's own format script against the directories containing changed files, then inspect the diff.

```sh
cd /workspaces/nss-dev/nss

# Run clang-format in-place on the directories that contain changed files,
# then use git diff to see any formatting violations.
bash automation/clang-format/run_clang_format.sh <dir1> [dir2 ...]
```

The script exits non-zero and prints the diff if any file needed reformatting. Record any violations (file name + line range is sufficient). Then restore the tree to a clean state before building:

```sh
git restore .
```

---

## Phase 5: Build and Test (UBSan + ASan combined)

UBSan and ASan can be enabled together in a single build. Build once, run the relevant tests once, and record results for both sanitizers.

The relevant tests are those identified in Phase 1; for ssl_gtest use a `GTESTFILTER`, for other suites use the appropriate script under `nss/tests/`.

**Build with both sanitizers:**
```sh
cd /workspaces/nss-dev/nss
./build.sh -c --ubsan --asan 2>&1 | tail -30
```
Record: build success/failure, any warnings in changed files.

**Run relevant tests:**

Expected: all tests pass, including any new test cases that failed in Phase 2. Record any UBSan errors (undefined behaviour reports) and ASan errors (heap/stack overflow, use-after-free, etc.) that appear in the test output.

After testing, restore a clean standard build for the remaining phases:
```sh
./build.sh -c 2>&1 | tail -20
```

---

## Phase 6: ABI Check

Check that the patch does not introduce unexpected ABI changes in the NSS shared libraries.

This phase requires `abidiff` (from the `abigail-tools` package). Check availability first:
```sh
which abidiff || echo "abidiff not found — install with: sudo apt-get install -y abigail-tools"
```
If unavailable and cannot be installed, skip this phase and note it in the summary.

**Step 1 — Save patched build artefacts.**
The standard build from Phase 5 is the "new" dist. Copy the shared libraries to a temporary location:
```sh
mkdir -p /tmp/nss-abi-new
cp /workspaces/nss-dev/dist/*/lib/lib*.so /tmp/nss-abi-new/
cp -r /workspaces/nss-dev/dist/public /tmp/nss-abi-new/
```

**Step 2 — Build the baseline.**
Temporarily remove the patch, build, save artefacts, then reapply:
```sh
cd /workspaces/nss-dev/nss
git stash          # remove patch temporarily
./build.sh -c 2>&1 | tail -20
mkdir -p /tmp/nss-abi-old
cp /workspaces/nss-dev/dist/*/lib/lib*.so /tmp/nss-abi-old/
cp -r /workspaces/nss-dev/dist/public /tmp/nss-abi-old/
git stash pop      # restore patch
./build.sh -c 2>&1 | tail -10   # restore patched dist
```

**Step 3 — Run abidiff for each shared library and compare against expected reports.**
The expected reports live in `nss/automation/abi-check/expected-report-<SO>.txt`. Any difference not already listed there is a new unexpected ABI change.

```sh
ALL_SOs="libfreebl3.so libfreeblpriv3.so libnspr4.so libnss3.so libnssckbi.so libnsssysinit.so libnssutil3.so libplc4.so libplds4.so libsmime3.so libsoftokn3.so libssl3.so"
for SO in $ALL_SOs; do
  [ -f /tmp/nss-abi-old/$SO ] || continue
  abidiff --hd1 /tmp/nss-abi-new/public --hd2 /tmp/nss-abi-new/public \
          /tmp/nss-abi-old/$SO /tmp/nss-abi-new/$SO \
    | grep -v "^Functions changes summary:" \
    | grep -v "^Variables changes summary:" \
    | sed 's/__anonymous_enum__[0-9]*/__anonymous_enum__/g' \
    > /tmp/nss-abi-report-$SO.txt
  diff -wB /workspaces/nss-dev/nss/automation/abi-check/expected-report-$SO.txt \
           /tmp/nss-abi-report-$SO.txt \
    && echo "$SO: OK" || echo "$SO: UNEXPECTED ABI CHANGES — see /tmp/nss-abi-report-$SO.txt"
done
```

Record: which libraries (if any) showed unexpected ABI changes, and a brief description of what changed.

---

## Phase 7: Fuzzing (Brief)

Only run fuzzers identified as relevant in Phase 1. Skip this phase if no relevant fuzzers were identified.

Build with fuzzing support:
```sh
cd /workspaces/nss-dev/nss
./build.sh --fuzz --disable-tests 2>&1 | tail -20
```

The fuzz binary is at `../dist/bin/nssfuzz` or similar. For each relevant fuzzer target, run for 30 seconds:
```sh
FUZZER_TARGET=<target>   # e.g. tls_client, tls_server, asn1, quickder, pkcs12
../dist/bin/nssfuzz $FUZZER_TARGET -max_total_time=30 -artifact_prefix=/tmp/fuzz-$FUZZER_TARGET- 2>&1 | tail -10
```

Record: any crashes or timeouts found. Note the exec/s rate as a sanity check that the fuzzer is running.

---

## Phase 8: Coverage Check

Build with coverage instrumentation and run the relevant tests to check that the new/changed code paths are exercised.

```sh
cd /workspaces/nss-dev/nss
./build.sh --clang --coverage 2>&1 | tail -20
```

Run the relevant tests, then generate a coverage report focused on the changed files:
```sh
cd /workspaces/nss-dev/nss/tests
HOST=localhost DOMSUF=localdomain USE_64=1 DIST=/workspaces/nss-dev/dist bash ssl_gtests/ssl_gtests.sh
```

Use `llvm-cov` or `lcov` to get line coverage for the specific files changed in the patch. Report percentage coverage and any uncovered lines that seem like they should be tested.

---

## Phase 9: Review Summary

Produce a structured review report covering all phases:

```
## NSS Bug $ARGUMENTS — Patch Review

### Patch Summary
[1-2 sentence description of what the patch does]

### Files Changed
[List of files and brief description of changes]

### clang-format (Phase 4)
- [CLEAN / violations found: ...]

### Test Verification
- Pre-patch (Phase 2): [new tests FAIL as expected / not applicable / UNEXPECTED PASS]
- Post-patch (Phase 5): [all tests PASS / failures listed]

### Sanitizer Results
- UBSan + ASan (Phase 5): [CLEAN / issues found: ...]

### ABI Check (Phase 6)
- [CLEAN / skipped (abidiff unavailable) / unexpected changes: ...]

### Fuzzing (Phase 7)
- Fuzzers run: [list or "N/A"]
- Crashes found: [none / list]

### Coverage (Phase 8)
- Changed files coverage: [X% / not measured]
- Uncovered lines of concern: [none / list]

### Code Quality Notes
[Any observations about the code changes: correctness, style, edge cases, missing error handling, etc.]

### Verdict
[APPROVE / NEEDS WORK / NEEDS DISCUSSION]

### Recommendations
[Numbered list of any issues that should be addressed before landing]
```
