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
  `analysis-python`, not `python3` -- see the interpreter table below)
- **Z3** -- SMT solver (`z3` CLI; Python bindings via `analysis-python`)

### Languages
- **Rust** (rustc, cargo)
- **Python 3**, **uv** (fast Python package manager; also manages standalone
  CPython builds, so a script can ask for a newer Python than the system one)
- **Node.js 24** (node, npm, npx)

### Which Python has what

The Python libraries are **not** all importable from one interpreter. Pick the
one that has the library you need:

| Interpreter | Has | Use it for |
|---|---|---|
| `python3` (`/usr/bin/python3`) | PyYAML | `#!/usr/bin/env python3` scripts, NSS's `./mach` |
| `analysis-python` | angr, z3, claripy, tlslite | binary analysis, SMT/constraint scripting, TLS interop |
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
  prefer apt, uv or pipx when both have the tool.

## Workspace Layout

```
/workspaces/project/     Your project (bind-mounted from host)
/.sccache/               Compiler cache (persists across container rebuilds)
```
