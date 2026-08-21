# Container Environment

You are running inside a sandboxed dev container. All your work should be done
in `/workspaces/project/`, which is bind-mounted from the host. Changes you
make there are written directly to the host filesystem.

The project may have its own CLAUDE.md with project-specific instructions.
Follow those instructions.

## Installed Tools

### Compilers & Build
- **Clang 18** (default) -- `CC="sccache clang"`, `CXX="sccache clang++"`
- **GCC 14** (gcc/g++/gfortran via `update-alternatives`)
- **build-essential**, **CMake**, **Ninja**, **gyp**, **pkg-config**
- **bear** -- generate `compile_commands.json`
- **sccache** -- compiler cache backed by a persistent volume at `/.sccache`.
  `CC` and `CXX` are wrapped in it (`CC="sccache clang"`), so any build that
  honours `CC`/`CXX` is cached automatically. Check it is being used with
  `sccache --show-stats`. A build system that needs a single-word `CC` (or that
  does its own sccache wrapping, like Mozilla's mozconfig) should set
  `CC=clang CXX=clang++` itself.

### Debugging & Static Analysis
- **gdb**, **valgrind**
- **clang-tidy**, **cppcheck**, **semgrep**
- **clang-format**
- **weggli** -- semantic C/C++ code search

### Testing & Fuzzing
- **AFL++** -- coverage-guided fuzzer
- **lcov**, **diff-cover** -- code coverage

### Binary & Constraint Analysis
- **angr** -- binary analysis / symbolic execution (run scripts with
  `angr-python`, not `python3` -- see the interpreter table below)
- **Z3** -- SMT solver (`z3` CLI; Python bindings via `angr-python`)

### Languages
- **Rust** (rustc, cargo)
- **Python 3**, **uv** (fast Python package manager)
- **Node.js 24** (node, npm, npx)

### Which Python has what

The Python libraries are **not** all importable from one interpreter. Each
pipx-installed tool lives in its own venv, so pick the interpreter that has
the library you need:

| Interpreter | Has | Use it for |
|---|---|---|
| `python3` (`/usr/bin/python3`) | PyYAML | `#!/usr/bin/env python3` scripts, NSS's `./mach` |
| `angr-python` | angr, z3, claripy | binary analysis, SMT/constraint scripting |
| `tlslite-python` | tlslite-ng | TLS interop scripting |
| `uv run --with <pkg>` | anything | one-off scripts needing a package none of the above has |

`angr-python` and `tlslite-python` are symlinks to the pipx venv
interpreters. The apt `z3` package is the CLI only -- Python `import z3` comes
from angr's venv.

### Documentation
- **Sphinx** (`sphinx-build`) -- documentation builder / linter, with the
  **myst-parser** extension injected (NSS's docs live in `doc/src` and are
  MyST Markdown; `./mach doc-lint` fails at config load without it)

### Profiling
- **profiler-cli** (also `pq`) -- query Firefox Profiler profiles from the
  command line; `profiler-cli guide` prints a usage walkthrough

### Networking
- **tlslite-ng** -- pure-Python TLS implementation (see the interpreter table)

### Source Control & Search
- **git**, **git-cinnabar** (Mercurial repos via git), **Mercurial**
- **searchfox-cli** -- query Mozilla's Searchfox code search

### File Watching
- **watchman** -- filesystem change watcher

### Editors
- **vim**, **micro**

### Terminal
- **tmux** -- terminal multiplexer

### Environment
- **direnv** -- automatic per-directory environment variables
- **Homebrew** -- package manager (Linuxbrew) at `/home/linuxbrew/.linuxbrew/`.
  It sits at the **back** of `PATH` so its dependency tree (its own python3,
  binutils, gfortran, openssl) cannot shadow the system toolchain. Anything
  installed with `brew install` only wins if nothing else provides that name;
  prefer apt or pipx when both have the tool.

## Workspace Layout

```
/workspaces/project/     Your project (bind-mounted from host)
/.sccache/               Compiler cache (persists across container rebuilds)
```
