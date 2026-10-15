FROM mcr.microsoft.com/devcontainers/base:1-ubuntu-22.04

# LLVM/Clang 18 — Ubuntu 22.04's packaged clang is too old (14) for sanitizer
# builds. Install from the official LLVM apt repository.
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        ca-certificates curl gnupg software-properties-common \
    && curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key \
        | gpg --dearmor -o /usr/share/keyrings/llvm.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/llvm.gpg] https://apt.llvm.org/jammy/ llvm-toolchain-jammy-18 main" \
        > /etc/apt/sources.list.d/llvm-18.list \
    && apt-get update \
    && apt-get -y install --no-install-recommends \
        clang-18 clang-format-18 clang-tidy-18 clang-tools-18 \
        lld-18 lldb-18 libclang-18-dev libclang-rt-18-dev libfuzzer-18-dev \
        llvm-18 llvm-18-dev \
    && for tool in clang clang++ clang-format clang-tidy clang-cpp lld lldb \
                   clangd asan_symbolize llvm-symbolizer llvm-ar llvm-nm llvm-objdump \
                   llvm-ranlib llvm-strip llvm-profdata llvm-cov; do \
        ln -sf "/usr/bin/${tool}-18" "/usr/local/bin/${tool}"; \
    done \
    && apt-get autoremove -y && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# GCC 14 — Ubuntu 22.04 ships GCC 11; add the Toolchain PPA for a modern version.
# On x86_64 also the multilib packages: 32-bit libc/libgcc so the
# i686-unknown-linux-gnu Rust target (and clang/gcc -m32) can link.
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends software-properties-common \
    && add-apt-repository -y ppa:ubuntu-toolchain-r/test \
    && apt-get update \
    && apt-get -y install --no-install-recommends \
        gcc-14 g++-14 gfortran-14 \
    && if [ "$(uname -m)" = x86_64 ]; then \
        apt-get -y install --no-install-recommends gcc-14-multilib g++-14-multilib; \
    fi \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 140 \
        --slave /usr/bin/g++ g++ /usr/bin/g++-14 \
        --slave /usr/bin/gfortran gfortran /usr/bin/gfortran-14 \
    && apt-get autoremove -y && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    && gcc --version

# Core build tools and common dependencies. CMake is deliberately absent —
# Ubuntu's 3.22 is too old; it is installed with uv further down.
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        build-essential \
        ninja-build \
        gyp \
        pkg-config \
        gdb \
        valgrind \
        cppcheck \
        python3 \
        python3-distutils \
        python3-yaml \
        pipx \
        zlib1g-dev \
        libsqlite3-dev \
        libgtk-3-dev \
        libasound2-dev \
        direnv \
        mercurial \
        perl \
        psmisc \
        procps \
        lcov \
        bear \
        vim \
        tmux \
        ca-certificates \
        curl \
    && apt-get autoremove -y && apt-get clean -y \
        && rm -rf /var/lib/apt/lists/* \
    && python3 -c "import yaml; print('PyYAML', yaml.__version__)"

# micro — terminal text editor
RUN curl -fsSL https://getmic.ro | bash \
    && mv micro /usr/local/bin/ \
    && micro --version

# diff-cover — show coverage diff between branches
RUN PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install diff-cover

# Modern git — Ubuntu 22.04 ships 2.34; the git-core PPA tracks the latest stable.
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && add-apt-repository -y ppa:git-core/ppa \
    && apt-get update \
    && apt-get -y install --no-install-recommends git \
    && apt-get autoremove -y && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    && git --version

# Install git-cinnabar (use Git to work with Mercurial repos)
RUN ARCH="$(uname -m)" \
    && case "$ARCH" in \
        x86_64)  CINNABAR_ARCH=x86_64 ;; \
        aarch64) CINNABAR_ARCH=arm64 ;; \
        *)       echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; \
    esac \
    && curl -sL "https://github.com/glandium/git-cinnabar/releases/download/0.7.3/git-cinnabar.linux.${CINNABAR_ARCH}.tar.xz" \
    | tar -xJ --strip-components=1 -C /usr/local/bin/ \
    && git cinnabar --version

# Install Rust toolchain under /usr/local, OWNED BY vscode. Root-owned homes
# made the toolchain read-only at runtime: `cargo build` failed with
# Permission denied writing the registry cache, and `rustup target add` /
# `rustup toolchain install` / `rustup component add` were impossible, which
# blocks cross targets, MSRV toolchains, nightly (Miri) and llvm-tools
# (coverage). As with the uv venv further down, the dirs are created for
# vscode and everything is installed as vscode rather than chowned afterwards
# — a recursive chown would duplicate the whole toolchain into a new layer.
# The cargo tools below are installed as vscode for the same reason: running
# them as root would leave root-owned files in CARGO_HOME.
#
# Stable uses the minimal profile plus clippy and rustfmt: the default profile
# adds rust-docs, ~900 MB of offline HTML that nothing in here reads.
#
# Every layer that runs cargo deletes $CARGO_HOME/registry and git (crate
# sources and downloads, ~700 MB across the tool installs) in the SAME RUN —
# deleting them in a later layer would not shrink the image. cargo simply
# re-downloads what a build needs at runtime. The final assertion checks no
# layer forgot.
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH="/usr/local/cargo/bin:$PATH"
RUN mkdir -p "$RUSTUP_HOME" "$CARGO_HOME" \
    && chown vscode:vscode "$RUSTUP_HOME" "$CARGO_HOME"
USER vscode
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --profile minimal --component clippy,rustfmt \
    && rustc --version

# Extra toolchains, targets and components that typical Rust CI matrices
# need: cross targets on stable, an MSRV toolchain, nightly with Miri, and
# llvm-tools for coverage. Pre-installed so they survive container rebuilds
# instead of being re-downloaded by every new container. The MSRV and nightly
# toolchains use the minimal profile — they only need to build and test.
# RUST_NIGHTLY can be pinned to a dated nightly (nightly-YYYY-MM-DD) for
# reproducible rebuilds; rustup already falls back to the newest nightly that
# ships every requested component, so an unpinned build will not break on a
# nightly that is missing Miri. `cargo miri setup` pre-builds Miri's sysroot
# (into ~/.cache/miri) so the first `cargo miri test` does not have to.
ARG RUST_MSRV=1.85.0
ARG RUST_NIGHTLY=nightly
RUN rustup target add wasm32-unknown-unknown i686-unknown-linux-gnu \
    && rustup component add llvm-tools-preview \
    && rustup toolchain install "$RUST_MSRV" --profile minimal \
    && rustup toolchain install "$RUST_NIGHTLY" --profile minimal --component miri,rust-src \
    && cargo "+$RUST_NIGHTLY" miri setup \
    && rustup toolchain list \
    && rm -rf "$CARGO_HOME/registry" "$CARGO_HOME/git"

# Cargo tools, installed with cargo-binstall: it downloads each crate's
# upstream release binaries (its crate-meta-data strategy) and only falls
# back to compiling when there are none. The quick-install strategy is
# disabled — it serves binaries built by a third party (cargo-quickinstall)
# rather than by the tool's own maintainers. binstall does not check glibc:
# cargo-mutants' upstream gnu binary needs glibc 2.39 (jammy has 2.35), so it
# is compiled with plain `cargo install` instead. The --version checks at the
# end exist to catch exactly that for any other tool.
#   bindgen-cli     Rust FFI bindings from C headers (-sys crates, e.g. bssl-sys);
#                   loads libclang 18 at runtime
#   cargo-hack      feature-powerset / MSRV checks
#   cargo-mutants   mutation testing
#   cargo-machete   unused-dependency detection
#   cargo-deny      license / advisory / duplicate-dependency policy
#   cargo-llvm-cov  source-based coverage (uses llvm-tools-preview)
#   cargo-nextest   faster test runner
#   cargo-fuzz      libFuzzer harnesses (runs on the nightly toolchain)
#   cargo-afl       AFL++ harnesses for Rust; builds its AFL++ runtime for the
#                   stable rustc as part of the install (no separate
#                   `cargo afl config --build` — it refuses to run once built)
RUN curl -L --proto '=https' --tlsv1.2 -sSf \
        https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh \
    | bash \
    && cargo binstall --no-confirm --locked --disable-strategies quick-install \
        bindgen-cli cargo-hack cargo-machete cargo-deny \
        cargo-llvm-cov cargo-nextest cargo-fuzz cargo-afl \
    && cargo install --locked cargo-mutants \
    && bindgen --version && cargo hack --version && cargo mutants --version \
    && cargo machete --version && cargo deny --version && cargo llvm-cov --version \
    && cargo nextest --version && cargo fuzz --version && cargo afl --version \
    && rm -rf "$CARGO_HOME/registry" "$CARGO_HOME/git"

# Install weggli (semantic C/C++ code search)
RUN cargo install weggli \
    && weggli --version \
    && rm -rf "$CARGO_HOME/registry" "$CARGO_HOME/git"

# Install searchfox-cli (query Mozilla's Searchfox code search from CLI)
RUN cargo install searchfox-cli \
    && searchfox-cli --help > /dev/null \
    && rm -rf "$CARGO_HOME/registry" "$CARGO_HOME/git"

# samply — sampling profiler; produces Firefox Profiler format, which the
# profiler-cli installed further down can then query. Installed here with the
# other cargo tools, deliberately *before* RUSTC_WRAPPER=sccache is set: at
# this point /.sccache does not exist yet (it is created near the end of the
# build) and sccache would try to make it at the filesystem root.
RUN cargo install --locked samply \
    && samply --version \
    && rm -rf "$CARGO_HOME/registry" "$CARGO_HOME/git"

# sccache — shared compiler cache, dramatically speeds up rebuilds.
# The cache directory is backed by a named volume so it survives container
# rebuilds. CC/CXX are wrapped in sccache: left unwrapped, the cache sat
# completely idle (0 compile requests across full NSS builds) while still
# being advertised as a compiler cache. Projects that do their own sccache
# wrapping (Mozilla's mozconfig, for instance) override CC/CXX anyway, so
# wrapping here only affects builds that would otherwise get no caching.
RUN cargo install sccache \
    && sccache --version \
    && rm -rf "$CARGO_HOME/registry" "$CARGO_HOME/git"
USER root

# CC/CXX point at single-path wrapper scripts rather than the two-word
# "sccache clang": plenty of build scripts hand $CC straight to
# -DCMAKE_C_COMPILER, which rejects anything that is not one path ("not a
# full path"). The wrappers are named exactly `clang`/`clang++` (in their own
# directory, not on PATH) so tools that sniff the compiler by basename still
# recognise it, and they call clang by absolute path so they cannot recurse.
RUN mkdir -p /usr/local/lib/sccache-wrap \
    && for c in clang clang++; do \
        printf '#!/bin/sh\nexec sccache /usr/local/bin/%s "$@"\n' "$c" \
            > "/usr/local/lib/sccache-wrap/$c"; \
        chmod 0755 "/usr/local/lib/sccache-wrap/$c"; \
    done

ENV SCCACHE_DIR=/.sccache \
    SCCACHE_CACHE_SIZE=5G \
    RUSTC_WRAPPER=sccache \
    CC=/usr/local/lib/sccache-wrap/clang \
    CXX=/usr/local/lib/sccache-wrap/clang++

# uv — fast Python package manager. It also manages standalone CPython builds,
# which is what makes the analysis venv below possible: angr requires Python
# >= 3.12 and this image's system python3 is Ubuntu 22.04's 3.10. The install
# dir and cache live under /opt/uv so both root (build time) and vscode
# (runtime) share one warm wheel cache.
ENV UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    UV_CACHE_DIR=/opt/uv/cache
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh \
    && uv --version

# CMake — Ubuntu 22.04 ships 3.22, and BoringSSL (built by bssl-sys) uses
# $<LIST:TRANSFORM>, which needs >= 3.27. The PyPI `cmake` package wraps
# Kitware's official binaries; installed as a uv tool, pinned. Runs as root
# with its own tool dir and --no-cache so nothing root-owned lands in the
# vscode-owned /opt/uv, and against the system python3 so it does not depend
# on the uv-managed interpreters either.
ARG CMAKE_VERSION=4.4.4
RUN UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin \
        uv tool install --no-cache --python /usr/bin/python3 "cmake==${CMAKE_VERSION}" \
    && cmake --version

# Python analysis libraries (angr, z3, tlslite-ng) live in ONE shared venv
# built by uv, not in a pipx venv each. pipx installs *applications* and
# deliberately hides their site-packages; these are wanted as *libraries* to
# import from ad-hoc scripts. pipx also had to build against the system
# python3 (3.10), which silently resolves to a years-old angr.
#
# The venv interpreter is exposed through wrapper scripts, NOT symlinks.
# CPython finds pyvenv.cfg by walking up from the directory of the path it was
# invoked as, so a symlink at /usr/local/bin/angr-python makes it search
# /usr/local/bin and /usr/local, find nothing, and silently fall back to the
# base interpreter's site-packages.
#
# Installing here also warms UV_CACHE_DIR with angr's whole wheel set, so
# ad-hoc `uv run --no-project --with angr script.py` resolves from cache.
#
# The venv and the uv dirs are built as vscode rather than chowned afterwards:
# a recursive chown over the managed interpreter and the wheel cache would
# copy several hundred MB into an extra layer.
ARG ANALYSIS_PYTHON=3.12
RUN mkdir -p /opt/uv /opt/venvs && chown vscode:vscode /opt/uv /opt/venvs
USER vscode
#
# CC/CXX/RUSTC_WRAPPER are unwrapped for this layer: everything here should
# install from a wheel, but if a package does fall back to a source build,
# sccache would try to create SCCACHE_DIR (/.sccache, not made until much
# later) as vscode and fail at the filesystem root for no useful reason.
RUN uv python install "$ANALYSIS_PYTHON" \
    && uv venv --python "$ANALYSIS_PYTHON" /opt/venvs/analysis \
    && env CC=clang CXX=clang++ RUSTC_WRAPPER= \
        uv pip install --python /opt/venvs/analysis/bin/python \
            angr z3-solver tlslite-ng
USER root
# Note: no continuation line inside a RUN may start with `from` (or any other
# Docker keyword — instructions are case-insensitive). The devcontainer CLI
# parses this file line by line to find the base image and does not honour
# backslash continuations, so a Python `from x import y` at the start of a
# line makes it try to `docker pull x`. Hence `import importlib.metadata as m`.
# angr 10 folded claripy into the angr package (`angr.claripy`); a bare
# `import claripy` no longer works.
RUN for name in analysis-python angr-python tlslite-python; do \
        printf '#!/bin/sh\nexec /opt/venvs/analysis/bin/python "$@"\n' \
            > "/usr/local/bin/$name"; \
        chmod 0755 "/usr/local/bin/$name"; \
    done \
    && analysis-python -c "import angr, angr.claripy, z3, tlslite" \
    && analysis-python -c "import importlib.metadata as m; \
        pkgs = ['angr', 'z3-solver', 'tlslite-ng']; \
        print(' '.join(p + ' ' + m.version(p) for p in pkgs))"

# Z3 — SMT solver (constraint reasoning over bit-vectors, modular arithmetic)
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends z3 libz3-dev \
    && apt-get autoremove -y && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    && z3 --version

# AFL++ — coverage-guided fuzzer
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends afl++ \
    && apt-get autoremove -y && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    && afl-fuzz --version || true

# semgrep — pattern-based static analysis
RUN PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install semgrep

# Sphinx — documentation builder. Required by NSS's `./mach doc-lint`, which
# shells out to `sphinx-build`. The docs moved from doc/rst to doc/src and are
# written in MyST Markdown now, so doc/src/conf.py loads the myst_parser
# extension; without it every doc-lint run fails at config time. myst_parser
# is the only extension conf.py requires.
RUN PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install sphinx \
    && PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx inject sphinx myst-parser \
    && sphinx-build --version \
    && /opt/pipx/venvs/sphinx/bin/python -c "import myst_parser; print('myst-parser', myst_parser.__version__)"

# watchman — filesystem change watcher. Ubuntu's 4.9.0: old, but under 1 MB
# and linked against the system OpenSSL. It used to come from Homebrew, whose
# dependency tree for it (gcc, boost, binutils, python, openssl...) cost
# ~1.9 GB and shadowed ~70 system binaries until brew was moved to the back
# of PATH. Facebook's prebuilt Linux zips are no alternative on jammy:
# releases after 2024.04 need glibc 2.38 (jammy has 2.35), and the older ones
# link OpenSSL 1.1, which jammy does not ship.
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends watchman \
    && apt-get autoremove -y && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    && watchman --version

# Node.js 24 (LTS) — Ubuntu 22.04 has no node at all, and @firefox-devtools/
# profiler-cli below requires >= 24. Installed from the official tarball
# rather than an apt repo so the version is pinned and arch-explicit.
ARG NODE_VERSION=24.19.0
RUN ARCH="$(uname -m)" \
    && case "$ARCH" in \
        x86_64)  NODE_ARCH=x64 ;; \
        aarch64) NODE_ARCH=arm64 ;; \
        *)       echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; \
    esac \
    && mkdir -p /usr/local/lib/nodejs \
    && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" \
    | tar -xJ --strip-components=1 -C /usr/local/lib/nodejs \
    && for tool in node npm npx; do \
        ln -sf "/usr/local/lib/nodejs/bin/${tool}" "/usr/local/bin/${tool}"; \
    done \
    && node --version \
    && npm --version

# profiler-cli — query Firefox Profiler profiles from the command line
# (also available as `pq`). Installed with --prefix /usr/local so its
# binaries land in /usr/local/bin alongside everything else.
RUN npm install -g --prefix /usr/local @firefox-devtools/profiler-cli \
    && npm cache clean --force \
    && profiler-cli --version \
    && pq --version

# Claude Code is intentionally NOT installed here. Baking it into the image
# would pin its version to whatever was latest at build time, and Docker's
# layer cache would keep reusing that layer on later builds since the
# installer command never changes. Instead it's installed in post-create.sh,
# which runs on every container (re)creation and always picks up the latest
# version. This just pre-declares where the installer will put the binary.
ENV PATH="/home/vscode/.local/bin:$PATH"

# Create workspace and sccache directories.
# Volume mount points must be owned by vscode before volumes are attached,
# so that Docker preserves ownership when creating empty named volumes.
RUN mkdir -p /workspaces/project /.sccache \
    && chown -R vscode:vscode /workspaces /.sccache

# Rust environment assertion — runs as vscode, under the runtime env
# (RUSTC_WRAPPER=sccache, the sccache CC/CXX wrappers), because that is where
# Rust breaks in practice: root-owned homes, cargo subcommands that do not get
# along with a rustc wrapper, cross targets that cannot link. Builds a tiny
# lib+bin crate every way the pre-installed toolchains promise. SCCACHE_DIR is
# pointed at a temp dir: anything left in /.sccache would be copied into the
# named volume when Docker first creates it.
USER vscode
RUN set -eu; \
    fail() { echo "RUST ENVIRONMENT ASSERTION FAILED: $*" >&2; exit 1; }; \
    d="$(mktemp -d)"; export SCCACHE_DIR="$d/sccache"; \
    cargo new --quiet --vcs none --lib "$d/t"; cd "$d/t"; \
    printf '#[test]\nfn adds() { assert_eq!(2 + 2, 4); }\n' >> src/lib.rs; \
    printf 'fn main() { println!("ok"); }\n' > src/main.rs; \
    cargo test --quiet || fail "cargo test (stable, through sccache)"; \
    cargo build --quiet --target wasm32-unknown-unknown || fail "wasm32-unknown-unknown build"; \
    if [ "$(uname -m)" = x86_64 ]; then \
        cargo build --quiet --target i686-unknown-linux-gnu || fail "i686-unknown-linux-gnu build/link (multilib?)"; \
    fi; \
    cargo "+$RUST_MSRV" test --quiet || fail "cargo +$RUST_MSRV test"; \
    cargo "+$RUST_NIGHTLY" miri test --quiet || fail "cargo miri test"; \
    cargo llvm-cov --summary-only > /dev/null 2>&1 || fail "cargo llvm-cov"; \
    cargo nextest run > /dev/null 2>&1 || fail "cargo nextest run"; \
    sccache --stop-server > /dev/null 2>&1 || true; \
    cd /; rm -rf "$d" "$CARGO_HOME/registry" "$CARGO_HOME/git"; \
    echo "rust environment assertions passed"
USER root

# Final environment assertion —the smoke tests attached to the layers above
# only prove a tool worked *at the moment it was installed*. They cannot catch
# a later layer shadowing it: the `import yaml` check on the apt layer used to
# pass and then Homebrew, added much later, put a different python3 in front
# of it.
# This layer runs last, against the image's final PATH and env, and fails the
# build if what a user actually gets is broken. Add a check here whenever a new
# tool starts mattering.
#
# Runs as root, so keep it out of /.sccache — root-owned files in a volume
# mount point break the vscode user later.
RUN set -eu; \
    fail() { echo "ENVIRONMENT ASSERTION FAILED: $*" >&2; exit 1; }; \
    echo "== resolved binaries =="; \
    for tool in python3 clang clang++ gcc g++ gfortran ld as ar nm ranlib strip \
                objdump objcopy openssl make perl git node npm sccache; do \
        p="$(command -v "$tool")" || fail "$tool is not on PATH"; \
        case "$p" in /usr/bin/*|/usr/local/bin/*|/usr/local/cargo/bin/*) ;; \
            *) fail "$tool resolves outside the system/cargo bin dirs ($p) — shadowed?";; esac; \
        printf '  %-12s %s\n' "$tool" "$p"; \
    done; \
    [ "$(command -v python3)" = /usr/bin/python3 ] || fail "python3 is not /usr/bin/python3"; \
    python3 -c "import yaml" || fail "system python3 cannot import yaml (needed by ./mach)"; \
    clang --version | head -1 | grep -q ' 18\.' || fail "clang is not version 18"; \
    [ -x /usr/local/bin/clang ] || fail "/usr/local/bin/clang is missing (devcontainer.json C_Cpp.default.compilerPath points at it)"; \
    ld --version | head -1 | grep -q 'GNU ld' || fail "ld is not GNU binutils"; \
    watchman --version > /dev/null || fail "watchman does not run"; \
    for h in "$RUSTUP_HOME" "$CARGO_HOME"; do \
        bad="$(find "$h" ! -user vscode -print -quit)"; \
        [ -z "$bad" ] || fail "$h is not entirely owned by vscode ($bad) — cargo/rustup will fail at runtime"; \
    done; \
    [ ! -e "$CARGO_HOME/registry" ] || fail "$CARGO_HOME/registry was left in the image (~700 MB); delete it in the same RUN as the cargo command"; \
    echo "== toolchain =="; \
    d=/tmp/env-assert; rm -rf "$d"; mkdir -p "$d"; \
    printf '#include <stdio.h>\nint main(void){puts("ok");return 0;}\n' > "$d/t.c"; \
    printf '#include <string>\nint main(){return std::string("ok").size()?0:1;}\n' > "$d/t.cc"; \
    env SCCACHE_DIR="$d/sccache" $CC -O1 -c -o "$d/t.o" "$d/t.c" || fail "\$CC cannot compile C"; \
    env SCCACHE_DIR="$d/sccache" $CC -O1 -o "$d/t" "$d/t.o" || fail "\$CC cannot link"; \
    "$d/t" > /dev/null || fail "binary built by \$CC does not run"; \
    env SCCACHE_DIR="$d/sccache" $CXX -O1 -c -o "$d/tcc.o" "$d/t.cc" || fail "\$CXX cannot compile C++"; \
    clang -fsanitize=address -o "$d/tasan" "$d/t.c" || fail "clang cannot link an ASan build"; \
    cmv="$(cmake --version | awk 'NR==1 {print $3}')"; \
    printf '3.27\n%s\n' "$cmv" | sort -V -C || fail "cmake $cmv is older than 3.27 (BoringSSL needs \$<LIST:TRANSFORM>)"; \
    printf 'cmake_minimum_required(VERSION 3.27)\nproject(t C CXX)\nadd_executable(t t.c)\nadd_executable(tcc t.cc)\n' > "$d/CMakeLists.txt"; \
    env SCCACHE_DIR="$d/sccache" cmake -S "$d" -B "$d/build" -G Ninja \
        -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" > /dev/null \
        || fail "cmake rejects \$CC/\$CXX as CMAKE_<LANG>_COMPILER (must be a single full path)"; \
    env SCCACHE_DIR="$d/sccache" cmake --build "$d/build" > /dev/null || fail "cmake cannot build through \$CC/\$CXX"; \
    printf 'int answer(void);\n' > "$d/t.h"; \
    bindgen "$d/t.h" | grep -q 'fn answer' || fail "bindgen cannot generate bindings (libclang not found?)"; \
    reqs="$(env SCCACHE_DIR="$d/sccache" sccache --show-stats \
            | awk '$0 ~ /^Compile requests[[:space:]]/ {print $NF; exit}')"; \
    [ "${reqs:-0}" -ge 1 ] || fail "sccache saw no compile requests through \$CC/\$CXX (or --show-stats output no longer parses)"; \
    echo "  sccache compile requests: $reqs"; \
    env SCCACHE_DIR="$d/sccache" sccache --stop-server > /dev/null 2>&1 || true; \
    rm -rf "$d"; \
    echo "== python islands =="; \
    for py in analysis-python angr-python tlslite-python; do \
        "$py" -c "import angr, angr.claripy, z3, tlslite" \
            || fail "$py cannot import the analysis venv (angr/angr.claripy/z3/tlslite)"; \
        "$py" -c "import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)" \
            || fail "$py is older than Python 3.12 (angr requires >= 3.12)"; \
        printf '  %-16s %s\n' "$py" "$("$py" -c 'import sys; print(sys.version.split()[0], sys.prefix)')"; \
    done; \
    /opt/pipx/venvs/sphinx/bin/python -c "import myst_parser" || fail "sphinx venv is missing myst-parser"; \
    echo "== cli tools =="; \
    for tool in sphinx-build semgrep diff-cover weggli searchfox-cli micro uv \
                cargo rustc rustup bindgen cmake cargo-binstall cargo-hack cargo-mutants \
                cargo-machete cargo-deny cargo-llvm-cov cargo-nextest cargo-fuzz cargo-afl z3 afl-fuzz git-cinnabar profiler-cli pq bear samply; do \
        command -v "$tool" > /dev/null || fail "$tool is not on PATH"; \
    done; \
    echo "all environment assertions passed"
