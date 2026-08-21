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
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends software-properties-common \
    && add-apt-repository -y ppa:ubuntu-toolchain-r/test \
    && apt-get update \
    && apt-get -y install --no-install-recommends \
        gcc-14 g++-14 gfortran-14 \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 140 \
        --slave /usr/bin/g++ g++ /usr/bin/g++-14 \
        --slave /usr/bin/gfortran gfortran /usr/bin/gfortran-14 \
    && apt-get autoremove -y && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    && gcc --version

# Core build tools and common dependencies
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        build-essential \
        cmake \
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

# Install Rust toolchain (available to all users via /usr/local)
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH="/usr/local/cargo/bin:$PATH"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path \
    && chmod -R a+r /usr/local/rustup /usr/local/cargo \
    && rustc --version

# Install weggli (semantic C/C++ code search)
RUN cargo install weggli \
    && weggli --version

# Install searchfox-cli (query Mozilla's Searchfox code search from CLI)
RUN cargo install searchfox-cli \
    && searchfox-cli --help > /dev/null

# sccache — shared compiler cache, dramatically speeds up rebuilds.
# The cache directory is backed by a named volume so it survives container
# rebuilds. CC/CXX are wrapped in sccache: left unwrapped, the cache sat
# completely idle (0 compile requests across full NSS builds) while still
# being advertised as a compiler cache. Projects that do their own sccache
# wrapping (Mozilla's mozconfig, for instance) override CC/CXX anyway, so
# wrapping here only affects builds that would otherwise get no caching.
RUN cargo install sccache \
    && sccache --version

ENV SCCACHE_DIR=/.sccache \
    SCCACHE_CACHE_SIZE=5G \
    RUSTC_WRAPPER=sccache \
    CC="sccache clang" \
    CXX="sccache clang++"

# angr — binary analysis framework
RUN PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install angr

# tlslite-ng — pure-Python TLS implementation (for interop testing)
RUN PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install tlslite-ng

# pipx isolates every tool in its own venv, so `import angr`, `import z3` and
# `import tlslite` all fail from the system python3 even though the container
# advertises those libraries. Expose the venv interpreters under explicit
# names so scripts can reach them. z3's Python bindings come from angr's venv
# (angr depends on z3-solver); the apt z3 package is CLI-only.
RUN ln -sf /opt/pipx/venvs/angr/bin/python /usr/local/bin/angr-python \
    && ln -sf /opt/pipx/venvs/tlslite-ng/bin/python /usr/local/bin/tlslite-python \
    && angr-python -c "import angr, z3; print('angr + z3 ok')" \
    && tlslite-python -c "import tlslite; print('tlslite ok')"

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

# Homebrew (Linuxbrew) — used for packages not in Ubuntu repos
# The installer refuses to run as root, so switch to vscode for this step.
USER vscode
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    && /home/linuxbrew/.linuxbrew/bin/brew install watchman \
    && /home/linuxbrew/.linuxbrew/bin/watchman version
USER root

# Homebrew goes at the BACK of PATH, not the front. watchman's dependency tree
# drags in brew's own python3, binutils, gfortran and openssl, which between
# them shadow ~70 system binaries: `/usr/bin/env python3` stops seeing the
# system PyYAML (breaking `./mach`), and clang links every binary — sanitizer
# builds included — against brew's rolling ld instead of Ubuntu's binutils.
# Nothing brew installs here needs to win a name collision, and watchman has a
# full RPATH into the Cellar so it runs fine from the back of PATH.
ENV PATH="$PATH:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin"

# uv — fast Python package manager and runner
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh \
    && uv --version

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

# Final environment assertion — the smoke tests attached to the layers above
# only prove a tool worked *at the moment it was installed*. They cannot catch
# a later layer shadowing it: the `import yaml` check on the apt layer passes
# and then Homebrew, added much later, puts a different python3 in front of it.
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
        case "$p" in /home/linuxbrew/*) fail "$tool is shadowed by Homebrew ($p)";; esac; \
        printf '  %-12s %s\n' "$tool" "$p"; \
    done; \
    [ "$(command -v python3)" = /usr/bin/python3 ] || fail "python3 is not /usr/bin/python3"; \
    python3 -c "import yaml" || fail "system python3 cannot import yaml (needed by ./mach)"; \
    clang --version | head -1 | grep -q ' 18\.' || fail "clang is not version 18"; \
    [ -x /usr/local/bin/clang ] || fail "/usr/local/bin/clang is missing (devcontainer.json C_Cpp.default.compilerPath points at it)"; \
    ld --version | head -1 | grep -q 'GNU ld' || fail "ld is not GNU binutils"; \
    watchman --version > /dev/null || fail "watchman is not reachable from the back of PATH"; \
    echo "== toolchain =="; \
    d=/tmp/env-assert; rm -rf "$d"; mkdir -p "$d"; \
    printf '#include <stdio.h>\nint main(void){puts("ok");return 0;}\n' > "$d/t.c"; \
    printf '#include <string>\nint main(){return std::string("ok").size()?0:1;}\n' > "$d/t.cc"; \
    env SCCACHE_DIR="$d/sccache" $CC -O1 -c -o "$d/t.o" "$d/t.c" || fail "\$CC cannot compile C"; \
    env SCCACHE_DIR="$d/sccache" $CC -O1 -o "$d/t" "$d/t.o" || fail "\$CC cannot link"; \
    "$d/t" > /dev/null || fail "binary built by \$CC does not run"; \
    env SCCACHE_DIR="$d/sccache" $CXX -O1 -c -o "$d/tcc.o" "$d/t.cc" || fail "\$CXX cannot compile C++"; \
    clang -fsanitize=address -o "$d/tasan" "$d/t.c" || fail "clang cannot link an ASan build"; \
    reqs="$(env SCCACHE_DIR="$d/sccache" sccache --show-stats \
            | awk '$0 ~ /^Compile requests[[:space:]]/ {print $NF; exit}')"; \
    [ "${reqs:-0}" -ge 1 ] || fail "sccache saw no compile requests through \$CC/\$CXX (or --show-stats output no longer parses)"; \
    echo "  sccache compile requests: $reqs"; \
    env SCCACHE_DIR="$d/sccache" sccache --stop-server > /dev/null 2>&1 || true; \
    rm -rf "$d"; \
    echo "== python islands =="; \
    angr-python -c "import angr, z3" || fail "angr-python cannot import angr/z3"; \
    tlslite-python -c "import tlslite" || fail "tlslite-python cannot import tlslite"; \
    /opt/pipx/venvs/sphinx/bin/python -c "import myst_parser" || fail "sphinx venv is missing myst-parser"; \
    echo "== cli tools =="; \
    for tool in sphinx-build semgrep diff-cover weggli searchfox-cli micro uv \
                cargo rustc z3 afl-fuzz git-cinnabar profiler-cli pq bear; do \
        command -v "$tool" > /dev/null || fail "$tool is not on PATH"; \
    done; \
    echo "all environment assertions passed"
