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

# Install git-cinnabar (use Git to work with Mercurial repos)
RUN curl -sL https://github.com/glandium/git-cinnabar/releases/download/0.7.3/git-cinnabar.linux.x86_64.tar.xz \
    | tar -xJ --strip-components=1 -C /usr/local/bin/ \
    && git cinnabar --version

# Install weggli (semantic C/C++ code search)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && . "$HOME/.cargo/env" \
    && cargo install weggli \
    && cp "$HOME/.cargo/bin/weggli" /usr/local/bin/ \
    && rustup self uninstall -y

# Create workspace directory for NSS development
RUN mkdir -p /workspaces/nss-dev && chown vscode:vscode /workspaces/nss-dev
