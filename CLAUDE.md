# NSS Development Environment

## Project
This is a dev container for working on Mozilla NSS (Network Security Services) and NSPR (Netscape Portable Runtime).

## Directory Layout
- `/workspaces/nss-dev/nss/` — NSS source (git-cinnabar clone from hg.mozilla.org)
- `/workspaces/nss-dev/nspr/` — NSPR source (git-cinnabar clone from hg.mozilla.org)
- `/workspaces/config/` — Dev container configuration (do not modify from inside the container)

## Building NSS
```sh
cd /workspaces/nss-dev/nss
./build.sh
```
NSS uses gyp + ninja (not CMake). The `build.sh` script handles everything including building NSPR.

### Useful build flags
- `./build.sh -c` — clean build
- `./build.sh -g -v` — debug build, verbose
- `./build.sh --fuzz` — build with fuzzing support (libFuzzer)
- `./build.sh --asan` — build with AddressSanitizer
- `./build.sh --ubsan` — build with UndefinedBehaviorSanitizer

Build output goes to `../dist/`.

## Source Control
Repos are cloned via git-cinnabar. Use standard git commands — cinnabar translates to/from Mercurial transparently.

## Available Tools
- **clang/clang++** — default compiler
- **gcc/g++** — alternative compiler
- **gdb** — debugger
- **valgrind** — memory analysis
- **weggli** — semantic C/C++ code search (e.g. `weggli -R 'memcpy($buf, $src, $len)' nss/`)
- **clang-tidy, clang-format, cppcheck** — static analysis and formatting
- **bear** — generate `compile_commands.json` for IDE integration: `bear -- ./build.sh`
- **lcov** — code coverage

## NSS Code Conventions
- C11 / C++17
- NSS uses `PK11_*`, `SEC_*`, `CERT_*`, `NSS_*` prefixes for public APIs
- NSPR uses `PR_*` prefix
- Test binaries are in `nss/tests/` and run via `nss/tests/all.sh`
