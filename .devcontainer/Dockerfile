FROM mcr.microsoft.com/devcontainers/cpp:1-ubuntu-22.04

# Core build tools + NSS build dependencies
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        build-essential \
        cmake \
        ninja-build \
        gyp \
        pkg-config \
        gdb \
        valgrind \
        clang \
        clang-format \
        clang-tidy \
        clang-tools \
        cppcheck \
        # NSS-specific dependencies
        python3 \
        python3-distutils \
        zlib1g-dev \
        libsqlite3-dev \
        # Mercurial (needed by git-cinnabar)
        mercurial \
        # libFuzzer (LLVM fuzzing library)
        libfuzzer-14-dev \
        # Useful for NSS test harnesses
        perl \
        psmisc \
        procps \
        lcov \
        # Generate compile_commands.json for IDE integration with gyp/ninja builds
        bear \
        # Misc
        ca-certificates \
        curl \
    && apt-get autoremove -y && apt-get clean -y \
        && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 LTS (Ubuntu 22.04's packaged version is too old for Claude Code)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && node --version

# Install git-cinnabar (use Git to work with Mercurial repos)
RUN curl -sL https://github.com/glandium/git-cinnabar/releases/download/0.7.3/git-cinnabar.linux.x86_64.tar.xz \
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

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code \
    && claude --version

# Create workspace directory for NSS development
# Volume mount points must be owned by vscode before volumes are attached,
# so that Docker preserves ownership when creating empty named volumes.
RUN mkdir -p /workspaces/nss-dev /workspaces/nss-dev/nspr /workspaces/nss-dev/nss \
    && chown -R vscode:vscode /workspaces/nss-dev
