---
name: nss-systemize
description: Find systemic instances of a bug pattern across NSS. Use when the user says "/nss-systemize BUGNUM", "systemize bug XXXXX", "find similar bugs", or similar. Reads bug reports from bugs/, understands the defect class, then searches the entire codebase for the same pattern using grep, weggli, cppcheck, clang-tidy, and compiler warnings. Writes a report of all candidate locations.
version: 1.0.0
disable-model-invocation: true
---

# NSS Systemic Bug Search

Systemize bug: $ARGUMENTS

Follow each phase below in order. Be terse: if a phase completes without issues, just record the outcome and move on. Only provide detail when something is ambiguous or needs the user's attention.

**Report requirement**: You MUST write the report file when you complete the final phase. If the user continues the conversation and subsequent discussion reveals new information — reclassified findings, new candidates, revised confidence levels, confirmed false positives — update the report file to reflect the current best understanding. The report should always represent the most accurate and complete picture available.

**Before starting**, record the wall-clock start time:
```sh
date -u +%s
```

---

## Phase 0: Read the Bug

### 0a. Parse arguments

Parse `$ARGUMENTS` to extract one or more bug numbers. Accepted forms: `1234567`, `bug-1234567`, `bug 1234567`. If multiple bugs are given, process them together (they may be related).

Set `BUGNUM` to the primary bug number (first one given, or only one). If `$ARGUMENTS` is empty, use the latest folder under `/workspaces/nss-dev/bugs/` sorted by name.

### 0b. Read all bug context

Locate the bug folder. Check both `/workspaces/nss-dev/bugs/$BUGNUM/` and `/workspaces/nss-dev/bugs/bug-$BUGNUM/` — use whichever exists. If neither exists, **stop and ask the user** to fetch the bug data first. Do not proceed without bug context.

Once located, set `BUG_DIR` to the path and read everything available:
- `index.md` or any markdown summary — read in full
- All files in `attachments/` — read patches, test cases, crash logs, stack traces
- Any existing reports (`triage-report.md`, `bugfix-report.md`, `review.md`) — these contain prior analysis that saves re-deriving the defect class
- If multiple bugs were given, read all of them

---

## Phase 1: Characterize the Defect Pattern

This phase extracts a precise, searchable description of the bug class. Do not write any searches yet — first understand exactly what to look for.

### 1a. Identify the defect site

Read the relevant source code in `/workspaces/nss-dev/nss/`. Using bug report pointers, patches, and stack traces, identify:
- The **exact function** containing the defect
- The **exact lines** where the bug manifests
- The **fix** (if a patch exists) — what check, guard, or restructuring resolved it?

### 1b. Abstract the pattern

Generalize from the specific bug to a **defect pattern** — the structural code mistake that caused it. Be precise. Examples:

- "Length field read from untrusted input and used as a memcpy size without bounds check against remaining buffer"
- "Pointer returned by CERT_FindCertByName used after the owning CERTCertList is freed"
- "Loop iterates using a signed counter that can underflow to negative when extension length is zero"
- "Return value of PORT_Alloc not checked for NULL before dereference"
- "SSL extension parsed without verifying that the extension body length fits within the handshake message"

Write down:
1. **Pattern name**: A short label (e.g., "unchecked extension length", "missing NULL check after PORT_Alloc")
2. **Pattern description**: 2-3 sentences describing the structural mistake
3. **Key code elements**: The specific functions, macros, or idioms involved (e.g., `PORT_Alloc`, `ssl3_ConsumeHandshakeVariable`, `SECITEM_CopyItem`)
4. **What the fix looks like**: What distinguishes fixed code from vulnerable code (e.g., "a bounds check comparing length against remaining before the read")

### 1c. Determine the scope of the search

Decide which parts of the codebase are relevant. The bug pattern may be:
- **Subsystem-specific**: Only meaningful in one area (e.g., TLS extension parsing bugs → `lib/ssl/`)
- **API-specific**: Anywhere a particular function is called (e.g., missing error check after `PORT_Alloc` → entire codebase)
- **Structural**: A general C/C++ antipattern that could appear anywhere (e.g., signed/unsigned comparison in length checks)

Set `SEARCH_DIRS` accordingly — default to `lib/` but narrow or widen as the pattern demands.

---

## Phase 2: Search with Multiple Strategies

Use **every applicable** strategy below. Different tools catch different things — no single tool finds everything. Record all candidates from every strategy before filtering in Phase 3.

### Strategy A: Textual grep

Search for the specific functions, macros, or idioms identified in Phase 1. This catches exact matches and close variants.

```sh
cd /workspaces/nss-dev/nss
# Example: find all callers of a function that was misused
grep -rn "function_name" lib/ --include='*.c' --include='*.h'

# Example: find similar length-handling patterns
grep -rn "pattern_string" lib/ --include='*.c'
```

Run multiple targeted greps. For each hit, note the file, line, and surrounding context (use `grep -B2 -A5` to see context). Focus on:
- Same function called without the same guard the fix added
- Same data structure parsed with similar logic
- Same API used in the same potentially-unsafe way

### Strategy B: Semantic search with weggli

Weggli understands C syntax and finds structural patterns that grep misses. Construct patterns that capture the **shape** of the defect.

```sh
cd /workspaces/nss-dev/nss

# Example: find memcpy where length comes from attacker input without bounds check
weggli '{ _ = PORT_Alloc($len); }' lib/

# Example: find extension parsing that reads a length without checking remaining
weggli '{ $len = $buf[$off]; memcpy($dst, $src, $len); }' lib/

# Example: find return values that are not checked
weggli '{ $p = CERT_FindCert($arg); $p->$field; }' lib/
```

Write **2-5 weggli patterns** tailored to the specific defect. Start with a tight pattern matching the original bug closely, then broaden to catch variants:
1. **Exact pattern**: mirrors the original bug as closely as possible
2. **Relaxed pattern**: captures the same class with different variable names or slight structural differences
3. **Sibling pattern**: looks for the same mistake in related code (e.g., if the bug is in ClientHello parsing, search ServerHello parsing)

If a pattern returns too many results (>50), narrow it. If it returns zero, broaden it or try a different formulation. Record raw hit counts.

### Strategy C: cppcheck

Run cppcheck with checks relevant to the defect class. Use `--enable` flags targeted at the bug type.

```sh
cd /workspaces/nss-dev/nss

# Choose enables based on defect class:
# Buffer issues: --enable=warning,portability
# NULL derefs / uninitialized: --enable=warning,style
# All checks (slower): --enable=all

# Run on the relevant subdirectories only (full codebase is too slow)
cppcheck --enable=warning,portability \
  --suppress=missingInclude \
  --inconclusive \
  --force \
  -j$(nproc) \
  lib/ssl/ 2>&1 | tee /tmp/cppcheck-results.txt

# Filter for findings related to our defect class
grep -i "keyword_related_to_defect" /tmp/cppcheck-results.txt
```

Expand the directory list if the defect pattern is not subsystem-specific. Record all relevant findings.

### Strategy D: clang-tidy

Run clang-tidy with checks relevant to the defect class. This requires `compile_commands.json` — generate it if not present.

```sh
cd /workspaces/nss-dev/nss

# Generate compile_commands.json if needed
if [ ! -f compile_commands.json ]; then
  bear -- ./build.sh 2>&1 | tail -5
fi

# Choose checks based on defect class. Examples:
# Buffer/array issues: clang-analyzer-core.uninitialized.*,clang-analyzer-security.*
# NULL deref: clang-analyzer-core.NullDereference
# Memory: clang-analyzer-cplusplus.NewDelete*,clang-analyzer-unix.Malloc*
# General security: clang-analyzer-security.*

CHECKS="clang-analyzer-security.*,clang-analyzer-core.*"

# Run on only the files in the relevant directories
find lib/ssl -name '*.c' -o -name '*.cc' | head -50 | while read -r f; do
  clang-tidy -checks="-*,$CHECKS" -p . "$f" 2>/dev/null
done | tee /tmp/clang-tidy-results.txt

# Filter for relevant findings
grep -E "warning:|error:" /tmp/clang-tidy-results.txt | grep -i "keyword"
```

Adjust the `-checks` flag and target directories to match the defect class. Record all relevant findings.

### Strategy E: Compiler warnings

Build with aggressive warnings to catch related issues:

```sh
cd /workspaces/nss-dev/nss

# Choose warning flags based on defect class:
# Signed/unsigned: -Wsign-compare -Wsign-conversion
# Buffer: -Warray-bounds -Wstringop-overflow
# Format string: -Wformat-security
# General: -Wextra -Wconversion

# Build just the relevant library with extra warnings
# (This is a targeted check — not a full rebuild)
NSS_DIST_DIR=/workspaces/nss-dev/dist ./build.sh 2>&1 \
  | grep -E "warning:" \
  | grep -i "keyword_or_directory" \
  | tee /tmp/compiler-warnings.txt
```

If a targeted extra-warnings build is feasible (e.g., adding `-Wsign-compare` to one library's build flags), do that instead of relying on the default build. Record relevant warnings.

### Strategy F: Manual code inspection

For patterns that tools cannot express, manually read the **sibling code** — code that does the same kind of thing as the vulnerable code. Identify these by:

```sh
cd /workspaces/nss-dev/nss

# Find sibling functions (e.g., other extension handlers in the same file)
grep -n "function_pattern" lib/ssl/ssl3ext*.c

# Find other parsers for the same data type
grep -rn "struct_or_type_name" lib/ --include='*.c' | head -30
```

Read each sibling function and check whether it has the same guard that fixed the original bug. Note any that lack it.

---

## Phase 3: Deduplicate and Classify Findings

### 3a. Merge results

Combine all candidates from Phase 2 into a single list, deduplicating by file and line number. Multiple tools may flag the same location — merge these and note which tools caught it.

### 3b. Classify each candidate

For each unique location, determine:

1. **File and function**: Exact location
2. **Code snippet**: The relevant 3-10 lines (enough to see the pattern)
3. **Confidence level**:
   - **High**: The code clearly has the same structural defect as the original bug. No guard or check is present.
   - **Medium**: The code has a similar pattern but may be protected by an earlier check, different control flow, or the data may not be attacker-controlled. Needs human review.
   - **Low**: The tool flagged this but manual inspection suggests it is likely safe — e.g., the length is validated upstream, the pointer cannot be NULL in this context, or the code is dead.
4. **Why it matches**: 1 sentence explaining why this location has the same pattern
5. **Why it might be safe**: 1 sentence explaining any mitigating factors (if applicable)
6. **Reachability**: Can this code be reached with attacker-controlled input? (Yes / Possibly / Unlikely / No)

### 3c. Drop false positives

Remove candidates classified as **Low confidence AND not reachable with attacker input**. Keep everything else — err on the side of reporting. Note how many candidates were dropped and why.

---

## Phase 4: Prevention Strategies

This phase steps back from individual findings and considers how this **category** of defect could be systematically prevented from recurring. Think practically — recommend things that can actually be adopted in the NSS project.

### 4a. Compiler and build-level prevention

Could this class of bug be caught at compile time or prevented by build configuration changes?

- **Warning flags**: Is there a `-W` flag (e.g., `-Wsign-compare`, `-Wconversion`, `-Warray-bounds`, `-Wimplicit-fallthrough`) that would flag this pattern? Check whether NSS already enables it. If not, test whether enabling it on the affected subdirectory produces an acceptable number of warnings:
  ```sh
  cd /workspaces/nss-dev/nss
  # Test if a warning flag catches the pattern without excessive noise
  NSS_DIST_DIR=/workspaces/nss-dev/dist ./build.sh 2>&1 | grep -c "warning:"
  ```
- **Compiler sanitizers**: Would UBSan, ASan, MSan, or TSan catch this at runtime during testing? Note which sanitizer and which specific check (e.g., `unsigned-integer-overflow`, `bounds`).
- **Hardening flags**: Would `-D_FORTIFY_SOURCE=2`, `-fstack-protector-strong`, or `-ftrapv` help detect or mitigate exploitation?

### 4b. Static analysis prevention

Could static analysis tools be configured to catch this pattern automatically?

- **cppcheck**: Can a custom cppcheck rule or addon detect this pattern? If so, sketch the rule (a regex pattern or a cppcheck addon XML rule is sufficient).
- **clang-tidy**: Is there an existing clang-tidy check that covers this, or could a custom check be written? Name the specific check (e.g., `bugprone-signed-char-misuse`, `clang-analyzer-security.insecureAPI.*`).
- **Custom linter**: If no existing tool covers it, would a project-specific linter rule (e.g., a script that greps for the dangerous pattern and fails CI) be practical? How many false positives would it produce?

### 4c. Fuzzing and dynamic testing

Could improved fuzzing or testing catch this class of bug earlier?

- **Existing fuzzer coverage**: Do the current fuzz targets (`ls /workspaces/nss-dev/nss/fuzz/`) cover the code paths where this pattern appears? Check whether the findings from Phase 3 are in code reachable by existing fuzzers.
- **New fuzz targets**: Would a new or modified fuzz target help? Describe what it would target (e.g., "a fuzzer that feeds random extension data to the server-side extension parser").
- **Corpus improvements**: Would adding specific seed inputs to existing fuzzer corpora help reach the vulnerable code paths?
- **Structured testing**: Would a targeted gtest suite that systematically tests boundary conditions (zero-length, max-length, off-by-one) for this type of input catch these bugs? Is this practical given the number of similar code locations?

### 4d. Code design and API improvements

Could the code be structured to make this class of bug impossible or harder to introduce?

- **Safer API patterns**: Could a wrapper function, macro, or helper enforce the invariant that the bug violated? (e.g., a "safe read" function that always bounds-checks, a RAII-style resource holder that prevents use-after-free)
- **Existing safer alternatives**: Does NSS already have a safer API that should have been used instead? (e.g., `ssl3_ConsumeHandshakeVariable` vs. raw pointer arithmetic)
- **Type system enforcement**: Could types be used to distinguish checked from unchecked lengths, owned from borrowed pointers, etc.?
- **Code review checklists**: Is this the kind of pattern that should be on a reviewer checklist for the affected subsystem?

Keep recommendations practical. A suggestion to "rewrite the TLS stack in Rust" is not actionable. A suggestion to "add a `ssl_ReadBoundedLength()` helper that wraps the length-read-and-check pattern used in 14 locations" is.

### 4e. Summarize prevention recommendations

For each recommendation, note:
1. **What**: The specific change
2. **Effort**: Low (config change, CI rule) / Medium (new helper, test suite) / High (API redesign, major refactor)
3. **Coverage**: How many of the Phase 3 findings it would prevent, and whether it prevents future instances too
4. **False positive risk**: Would it generate noise that erodes trust in the check?

Rank recommendations by the ratio of coverage to effort — high-coverage, low-effort changes first.

---

## Phase 5: Write Report

**Record the end time:**
```sh
date -u +%s
```
Calculate elapsed wall-clock time from the start time recorded before Phase 0.

Create the directory if needed:
```sh
mkdir -p /workspaces/nss-dev/bugs/$BUGNUM
```

Write the report to `/workspaces/nss-dev/bugs/$BUGNUM/bigger-picture.md`:

```
# NSS Bug <BUGNUM> — Systemic Analysis

**Original defect**: [1-sentence summary of the original bug]
**Pattern name**: [short label from Phase 1]
**Pattern description**: [2-3 sentence description of the structural mistake]
**Search scope**: [directories searched]

## Original Bug

**Function**: `function_name` in `file.c:line`
**What was wrong**: [1-2 sentences]
**What the fix does**: [1-2 sentences — or "No fix yet" if only triaging]

## Search Methodology

| Strategy | Scope | Hits (raw) | Hits (after dedup/filter) |
|---|---|---|---|
| grep | [dirs] | [N] | [N] |
| weggli | [dirs] | [N] | [N] |
| cppcheck | [dirs] | [N] | [N] |
| clang-tidy | [dirs] | [N] | [N] |
| Compiler warnings | [dirs] | [N] | [N] |
| Manual inspection | [dirs] | [N] | [N] |

**Total unique candidates**: [N]
**Dropped as false positive**: [N]
**Reported**: [N]

## Findings

### High Confidence

#### 1. `function_name` — `lib/path/file.c:LINE`

**Pattern match**: [Why this has the same defect]
**Reachability**: [Yes / Possibly / Unlikely] — [brief explanation]
**Detected by**: [grep, weggli, etc.]

```c
// Relevant code snippet (3-10 lines)
```

[Repeat for each high-confidence finding, numbered sequentially]

### Medium Confidence

#### N. `function_name` — `lib/path/file.c:LINE`

**Pattern match**: [Why this looks similar]
**Mitigating factors**: [Why it might be safe]
**Reachability**: [Yes / Possibly / Unlikely]
**Detected by**: [tools]

```c
// Relevant code snippet
```

[Repeat for each medium-confidence finding]

### Low Confidence (Retained)

[Only low-confidence findings that ARE reachable with attacker input. Brief list format is fine:]

- `file.c:LINE` in `function` — [1 sentence]. Detected by [tool]. Possibly safe because [reason].

## Summary

**High confidence**: [N] locations with the same structural defect
**Medium confidence**: [N] locations that need human review
**Low confidence (retained)**: [N] locations that are probably safe but reachable
**Subsystems affected**: [list of lib/ subdirectories with findings]

### Recommended Actions

[Bulleted list of concrete next steps. Examples:]
- Fix the [N] high-confidence findings — they have the same bug
- Review the medium-confidence findings in `lib/foo/` — [reason they need human judgment]
- [Any other pattern-specific recommendations]

## Prevention Strategies

### Build / Compiler

[What warning flags, sanitizers, or hardening options would catch or mitigate this class of bug. Note whether NSS already enables them. If a flag was tested, report the noise level.]

### Static Analysis

[cppcheck rules, clang-tidy checks, or custom linter rules that could detect the pattern. Name specific checks. If a custom rule is sketched, include it.]

### Fuzzing and Testing

[New or improved fuzz targets, corpus seeds, or structured test suites that would catch this class of bug. Note which existing fuzzers already cover (or miss) the affected code paths.]

### Code Design

[Safer API wrappers, helper functions, type-level enforcement, or coding guidelines that would make this class of bug harder to introduce. Keep it practical.]

### Ranked Recommendations

| # | Recommendation | Effort | Coverage | False positive risk |
|---|---|---|---|---|
| 1 | [highest value recommendation] | Low/Med/High | [N findings + future prevention] | Low/Med/High |
| 2 | ... | ... | ... | ... |

## Timing

| Metric | Value |
|---|---|
| Wall time | [Xm Ys] |
```

After writing the report, print:
1. The path to the saved report file.
2. A brief summary: how many high/medium/low findings, which subsystems are affected, and the top recommendation.
