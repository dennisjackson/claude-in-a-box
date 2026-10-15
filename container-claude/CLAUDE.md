# Container Environment

You are running inside a sandboxed dev container. All your work should be done
in `/workspaces/project/`, which is bind-mounted from the host. Changes you
make there are written directly to the host filesystem.

The project may have its own CLAUDE.md with project-specific instructions.
Follow those instructions.

## Installed Tools

### Compilers & Build
- **Clang 18** (default) -- `CC=/usr/local/lib/sccache-wrap/clang`,
  `CXX=/usr/local/lib/sccache-wrap/clang++` (sccache wrappers, see below)
- **GCC 14** (gcc/g++/gfortran via `update-alternatives`)
- **build-essential**, **CMake** (a pinned 4.x release installed with
  uv, not Ubuntu's 3.22), **Ninja**, **gyp**, **pkg-config**
- **bear** -- generate `compile_commands.json`
- **sccache** -- compiler cache backed by a persistent volume at `/.sccache`.
  `CC` and `CXX` are single-path wrapper scripts that run
  `sccache /usr/local/bin/clang[++]`, so any build that honours `CC`/`CXX` is
  cached automatically, and `$CC` can be passed straight to
  `-DCMAKE_C_COMPILER`. Check it is being used with `sccache --show-stats`. A
  build that does its own sccache wrapping (Mozilla's mozconfig,
  `CMAKE_<LANG>_COMPILER_LAUNCHER=sccache`) should set `CC=clang CXX=clang++`
  itself so sccache is not stacked on sccache.

### Debugging & Static Analysis
- **gdb**, **valgrind**
- **clang-tidy**, **cppcheck**, **semgrep**
- **clang-format**
- **weggli** -- semantic C/C++ code search

### Testing & Fuzzing
- **AFL++** -- coverage-guided fuzzer (for Rust targets: `cargo afl`,
  `cargo fuzz` -- see Languages)
- **lcov**, **diff-cover** -- code coverage

### Binary & Constraint Analysis
- **angr** -- binary analysis / symbolic execution (run scripts with
  `analysis-python`, not `python3` -- see the interpreter table below)
- **Z3** -- SMT solver (`z3` CLI; Python bindings via `analysis-python`)

### Languages
- **Rust** (rustup, rustc, cargo). `RUSTC_WRAPPER=sccache` is set.
  Pre-installed:
  - **stable** (default) with clippy and rustfmt (no offline `rust-docs`),
    targets `wasm32-unknown-unknown` and
    `i686-unknown-linux-gnu` (32-bit linking works via gcc multilib, x86_64
    hosts only) and the `llvm-tools-preview` component
  - **1.85.0** (MSRV; minimal profile) -- `cargo +1.85.0 test`
  - **nightly** with `miri` and `rust-src`; Miri's sysroot is pre-built --
    `cargo +nightly miri test`
  - `RUSTUP_HOME` (`/usr/local/rustup`) and `CARGO_HOME` (`/usr/local/cargo`)
    are owned by you, so further `rustup target add` / `toolchain install` /
    `component add` and `cargo install` work directly -- no need to redirect
    `CARGO_HOME`. Anything you add this way is lost when the container is
    rebuilt.
- **Cargo tools** (installed with **cargo-binstall**, which is also available
  for adding more -- `cargo binstall <crate>`):
  - **bindgen** (`bindgen-cli`) -- Rust FFI bindings from C headers, using
    libclang 18
  - **cargo-hack** -- feature-powerset and MSRV checks
  - **cargo-mutants** -- mutation testing
  - **cargo-machete** -- unused-dependency detection
  - **cargo-deny** -- license / advisory / duplicate-dependency policy
  - **cargo-llvm-cov** -- source-based coverage
  - **cargo-nextest** -- faster test runner
  - **cargo-fuzz** -- libFuzzer harnesses (needs `+nightly`)
  - **cargo-afl** -- AFL++ harnesses for Rust; its runtime is pre-built for
    the stable toolchain (for another toolchain, run `cargo +<toolchain> afl config --build`)
- **Python 3**, **uv** (fast Python package manager; also manages standalone
  CPython builds, so a script can ask for a newer Python than the system one)
- **Node.js 24** (node, npm, npx)

### Which Python has what

The Python libraries are **not** all importable from one interpreter. Pick the
one that has the library you need:

| Interpreter | Has | Use it for |
|---|---|---|
| `python3` (`/usr/bin/python3`) | PyYAML | `#!/usr/bin/env python3` scripts, NSS's `./mach` |
| `analysis-python` | angr (claripy is `angr.claripy` since angr 10), z3, tlslite | binary analysis, SMT/constraint scripting, TLS interop |
| `uv run --no-project --with <pkg>` | anything | one-off scripts needing a package neither of the above has |

`analysis-python` is a shared venv at `/opt/venvs/analysis` running a
uv-managed **Python 3.12** -- angr requires >= 3.12 and the system `python3`
is 3.10, so it cannot host angr at all. `angr-python` and `tlslite-python`
are aliases for the same interpreter. All three are wrapper scripts, not
symlinks: symlinking a venv interpreter elsewhere makes CPython miss
`pyvenv.cfg` and silently fall back to the base site-packages.

The apt `z3` package is the CLI only -- Python `import z3` comes from the
analysis venv.

To add a library permanently:

```sh
uv pip install --python /opt/venvs/analysis/bin/python <pkg>
```

For a throwaway script, declare the dependency inline (PEP 723) and let uv
build the environment -- uv's cache is pre-warmed with angr's wheels, and it
will fetch and manage any other interpreter version a script asks for:

```python
# /// script
# requires-python = ">=3.12"
# dependencies = ["angr"]
# ///
```

then `uv run --no-project script.py`. Pass `--no-project` so uv does not try
to sync a `pyproject.toml` it finds in the project tree.

### Documentation
- **Sphinx** (`sphinx-build`) -- documentation builder / linter, with the
  **myst-parser** extension injected (NSS's docs live in `doc/src` and are
  MyST Markdown; `./mach doc-lint` fails at config load without it)

### Profiling
- **samply** -- sampling profiler (`samply record <command>`). It writes
  Firefox Profiler format, so `profiler-cli` can query the result directly.
  There is no browser in this container, so save the profile to a file rather
  than letting samply open the profiler UI -- check `samply record --help` for
  the current flag. Profiling needs `perf_event_open`, which the seccomp
  profile allows, but the host sysctl `kernel.perf_event_paranoid` has the
  final say and cannot be changed from in here: at `1` (the value this
  container expects) you can profile processes you start, at `>= 2` you get no
  kernel stacks. If a recording fails with a permissions error, that sysctl is
  why -- report it rather than trying to work around it.
- **profiler-cli** (also `pq`) -- query Firefox Profiler profiles from the
  command line; `profiler-cli guide` prints a usage walkthrough

### Networking
- **tlslite-ng** -- pure-Python TLS implementation (see the interpreter table)

### Source Control & Search
- **git**, **git-cinnabar** (Mercurial repos via git), **Mercurial**
- **searchfox-cli** -- query Mozilla's Searchfox code search

### File Watching
- **watchman** -- filesystem change watcher (Ubuntu's 4.9.0)

### Editors
- **vim**, **micro**

### Terminal
- **tmux** -- terminal multiplexer

### Environment
- **direnv** -- automatic per-directory environment variables

## Workspace Layout

```
/workspaces/project/     Your project (bind-mounted from host)
/.sccache/               Compiler cache (persists across container rebuilds)
```
