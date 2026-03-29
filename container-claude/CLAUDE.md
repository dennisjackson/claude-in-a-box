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

## NSS Code Conventions
- C11 / C++17
- NSS uses `PK11_*`, `SEC_*`, `CERT_*`, `NSS_*` prefixes for public APIs
- NSPR uses `PR_*` prefix
- Test binaries are in `nss/tests/` and run via `nss/tests/all.sh`

## Keeping This File Up to Date
When something surprising or non-obvious is discovered about how to build, test, or work in this environment, update this file. The goal is that future sessions should not have to rediscover the same things.
