# NSS Development Environment

## IMPORTANT: Always Use a Worktree
**Before doing ANY work** (reading code to make changes, building, testing, applying patches, etc.), create a git worktree. NEVER modify files directly in `/workspaces/nss-dev/nss/`. The main checkout must stay clean.

```sh
# 1. Create the worktree (use a descriptive name, e.g. bug number or feature)
git -C /workspaces/nss-dev/nss worktree add --detach /workspaces/nss-dev/worktrees/<name>
# 2. Symlink NSPR so build.sh can find it
ln -sfn /workspaces/nss-dev/nspr /workspaces/nss-dev/worktrees/nspr
# 3. Do all work inside the worktree
cd /workspaces/nss-dev/worktrees/<name>
# 4. Build with a separate dist directory
NSS_DIST_DIR=/workspaces/nss-dev/dist-<name> ./build.sh
# 5. Run tests against the matching dist
cd tests
DIST=/workspaces/nss-dev/dist-<name> HOST=localhost DOMSUF=localdomain USE_64=1 bash ssl_gtests/ssl_gtests.sh
```

Clean up when done: `git -C /workspaces/nss-dev/nss worktree remove /workspaces/nss-dev/worktrees/<name>`

## Project
This is a dev container for working on Mozilla NSS (Network Security Services) and NSPR (Netscape Portable Runtime).

## Directory Layout
- `/workspaces/nss-dev/nss/` — NSS source (git-cinnabar clone from hg.mozilla.org)
- `/workspaces/nss-dev/nspr/` — NSPR source (git-cinnabar clone from hg.mozilla.org)
- `/workspaces/nss-dev/bugs/` — Bug context fetched from Bugzilla (markdown summaries, attachments, patches). Each bug lives in `bugs/bug-<id>/` with patches in `attachments/`.
- `/workspaces/nss-dev/.nss-exchange.git/` — Bare git repo shared with the host (the `exchange` remote). Push finished branches here.
- `/workspaces/nss-dev/dist/` — Default build output directory
- `/workspaces/config/` — Dev container configuration (do not modify from inside the container)

## Building NSS
```sh
cd /workspaces/nss-dev/nss
./build.sh
```
NSS uses gyp + ninja (not CMake). The `build.sh` script handles everything including building NSPR.

### Parallel / isolated builds
Set `NSS_DIST_DIR` to use a non-default output directory (useful for working on multiple branches simultaneously):
```sh
NSS_DIST_DIR=/workspaces/nss-dev/dist-mybranch ./build.sh
```
Pass the matching `DIST` when running tests:
```sh
DIST=/workspaces/nss-dev/dist-mybranch HOST=localhost DOMSUF=localdomain USE_64=1 bash ssl_gtests/ssl_gtests.sh
```

### Useful build flags
- `./build.sh -c` — clean build
- `./build.sh -g -v` — debug build, verbose
- `./build.sh --fuzz --disable-tests` — build with fuzzing support (libFuzzer); always use `--disable-tests` for fuzz builds
- `./build.sh --fuzz=tls --disable-tests` — fuzz build in Totally Lacking Security mode (required for TLS/DTLS client/server fuzzers)
- `./build.sh --asan` — build with AddressSanitizer
- `./build.sh --ubsan` — build with UndefinedBehaviorSanitizer
- `./build.sh --ubsan --asan` — combine sanitizers in a single build (both work together)

Build output goes to `../dist/`.

## Source Control
Repos are cloned via git-cinnabar. Use standard git commands — cinnabar translates to/from Mercurial transparently.

## Delivering Output

There are two output channels. Use the right one for the type of output.

### Patches → commit on a descriptive branch in the worktree

Commit finished work on a well-named branch in the worktree. The NSS repo has
a git remote called `exchange` pointing at a shared bare repo
(`.nss-exchange.git`). The user can push to it when they're ready for the host
to pick up the work. **Do not push to exchange automatically** — always leave
that to the user.

```sh
# Commit work on the branch in the worktree
cd /workspaces/nss-dev/worktrees/<name>
git checkout -b <branch-name>
git add ... && git commit ...

# When the user is ready to send it to the host:
git push exchange <branch-name>
```

**Branch naming**: Use descriptive branch names that include the bug number:
`bug-1234567-fix-tls-extension-overread`, `bug-1234567-add-sni-length-check`.

**Commit messages**: Follow NSS convention:
```
Bug 1234567 - Short imperative description of the change r=#nss-reviewers

Optional longer explanation of what was wrong and what this patch does.
Keep it concise — the reviewer can read the diff.
```

- First line: `Bug NNNNNN - Description r=#nss-reviewers` (capital B, space after dash, reviewer string at end)
- Keep the first line under ~72 characters
- Separate fix and test into two commits (fix first, test second)
- Do NOT include any Co-Authored-By trailer

### Analysis and comments → write to `bugs/`

Non-patch output — analysis reports, review summaries, prepared Bugzilla
comments, coverage reports, investigation notes — goes in the bugs folder:

```
/workspaces/nss-dev/bugs/<bugnum>/
├── bugfix-report.md      # fix summary from /nss-bugfix
├── review.md             # review summary from /nss-review
├── analysis.md           # investigation notes, root cause analysis
├── bugzilla-comment.md   # prepared comment for posting to Bugzilla
├── coverage-report.html  # diff-cover output
└── ...
```

Use clear, descriptive filenames. The host user will review these before acting
on them (e.g., posting a comment to Bugzilla).

## Available Tools
- **clang/clang++** — default compiler
- **gcc/g++** — alternative compiler
- **gdb** — debugger
- **valgrind** — memory analysis
- **weggli** — semantic C/C++ code search (e.g. `weggli -R 'memcpy($buf, $src, $len)' nss/`)
- **clang-tidy, clang-format, cppcheck** — static analysis and formatting
- **bear** — generate `compile_commands.json` for IDE integration: `bear -- ./build.sh`
- **lcov** — code coverage
- **diff-cover** — coverage focused on lines changed by a patch/diff

## Running Tests

### Running all tests
```sh
cd /workspaces/nss-dev/nss/tests
HOST=localhost DOMSUF=localdomain bash all.sh
```

### Running ssl gtests
Do **not** invoke `ssl_gtest` directly — it requires a cert DB populated by the test harness. Use:
```sh
cd /workspaces/nss-dev/nss/tests
HOST=localhost DOMSUF=localdomain USE_64=1 DIST=/workspaces/nss-dev/dist bash ssl_gtests/ssl_gtests.sh
```
The script creates the DB, generates all test certificates, then runs the binary. Running `ssl_gtest` directly (even against a manually created DB) will fail with certificate loading errors and likely crash.

### Running a specific gtest suite by name
Set `GTESTFILTER` to a gtest filter expression:
```sh
HOST=localhost DOMSUF=localdomain USE_64=1 DIST=/workspaces/nss-dev/dist GTESTFILTER="TlsConnectTest.*" bash ssl_gtests/ssl_gtests.sh
```

### Other individual test scripts
Each test has its own script under `nss/tests/` (e.g. `ssl/ssl.sh`, `cert/cert.sh`). They all require `HOST` and `DOMSUF` to be set.

### Code coverage
Use `./mach test-coverage` for line coverage — do **not** pass coverage flags directly to `build.sh` (it does not work).
```sh
cd /workspaces/nss-dev/nss
./mach test-coverage --test ssl_gtests 2>&1 | tee /tmp/coverage.log
# Extract the LCOV file path from output
grep "Coverage LCOV data:" /tmp/coverage.log
```
To see coverage for only the lines changed by a patch, use `diff-cover`:
```sh
diff-cover <lcov-file> --diff-file <patch.diff> --html-report report.html
```

### Fuzzing
Fuzz binaries are named `nssfuzz-<target>` under `$DIST/Debug/bin/`. List available targets:
```sh
ls /workspaces/nss-dev/dist/Debug/bin/nssfuzz-*
```
Run a target (e.g. for 30 seconds):
```sh
/workspaces/nss-dev/dist/Debug/bin/nssfuzz-tls-client -max_total_time=30
```
TLS/DTLS fuzzers require `--fuzz=tls` builds; other targets use `--fuzz`. Always list the available targets rather than assuming — there are fuzzers for certificates, PKCS, hashing, and other subsystems beyond TLS.

## Formatting
Check C/C++ files without modifying them:
```sh
clang-format --dry-run --Werror path/to/file.c
```

## NSS Code Conventions
- C11 / C++17
- NSS uses `PK11_*`, `SEC_*`, `CERT_*`, `NSS_*` prefixes for public APIs
- NSPR uses `PR_*` prefix
- Test binaries are in `nss/tests/` and run via `nss/tests/all.sh`

## Comments Policy
Use comments very sparingly. Do not add bug-specific comments in code or tests
(e.g., "This tests bug 1234567" or "Fixed: the length was not checked"). Good
reasons to comment:
- **High-level intent** that is not obvious from the code ("This parser must
  tolerate trailing padding because older implementations emit it")
- **Surprising behavior** that a future reader would otherwise misunderstand
  ("Returns SECSuccess even on empty input — callers depend on this")

If the code is clear, no comment is needed. Commit messages are the right place
for bug context, not inline comments.

## Keeping This File Up to Date
When something surprising or non-obvious is discovered about how to build, test, or work in this environment, update this file. The goal is that future sessions should not have to rediscover the same things.
