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
                   asan_symbolize llvm-symbolizer llvm-ar llvm-nm llvm-objdump \
                   llvm-ranlib llvm-strip llvm-profdata llvm-cov; do \
        ln -sf "/usr/bin/${tool}-18" "/usr/local/bin/${tool}"; \
    done \
    && apt-get autoremove -y && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

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
        && rm -rf /var/lib/apt/lists/*

# micro — terminal text editor
RUN curl -fsSL https://getmic.ro | bash \
    && mv micro /usr/local/bin/ \
    && micro --version

# diff-cover — show coverage diff between branches
RUN PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install diff-cover


# Install Node.js 22 LTS (Ubuntu 22.04's packaged version is too old for Claude Code)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && node --version

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
# rebuilds. sccache is available but not wired into CC/CXX by default,
# because projects like Mozilla manage their own sccache wrapping.
RUN cargo install sccache \
    && sccache --version

ENV SCCACHE_DIR=/.sccache \
    SCCACHE_CACHE_SIZE=5G \
    RUSTC_WRAPPER=sccache \
    CC=clang \
    CXX=clang++

# angr — binary analysis framework
RUN PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install angr

# tlslite-ng — pure-Python TLS implementation (for interop testing)
RUN PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install tlslite-ng

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

# Homebrew (Linuxbrew) — used for packages not in Ubuntu repos
# The installer refuses to run as root, so switch to vscode for this step.
USER vscode
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    && /home/linuxbrew/.linuxbrew/bin/brew install watchman \
    && /home/linuxbrew/.linuxbrew/bin/watchman version
USER root

ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH"

# uv — fast Python package manager and runner
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh \
    && uv --version

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code \
    && claude --version

# Create workspace and sccache directories.
# Volume mount points must be owned by vscode before volumes are attached,
# so that Docker preserves ownership when creating empty named volumes.
RUN mkdir -p /workspaces/project /.sccache \
    && chown -R vscode:vscode /workspaces /.sccache
