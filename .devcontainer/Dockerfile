FROM mcr.microsoft.com/devcontainers/cpp:1-ubuntu-22.04

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
        lld-18 lldb-18 libclang-rt-18-dev libfuzzer-18-dev \
    && for tool in clang clang++ clang-format clang-tidy clang-cpp lld lldb \
                   asan_symbolize llvm-symbolizer llvm-ar llvm-nm llvm-objdump \
                   llvm-ranlib llvm-strip; do \
        ln -sf "/usr/bin/${tool}-18" "/usr/local/bin/${tool}"; \
    done \
    && apt-get autoremove -y && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

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
        cppcheck \
        # NSS-specific dependencies
        python3 \
        python3-distutils \
        zlib1g-dev \
        libsqlite3-dev \
        # Mercurial (needed by git-cinnabar)
        mercurial \
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

# ccache — dramatically speeds up rebuilds by caching object files.
# The cache directory is backed by a named volume so it survives container
# rebuilds. We set CC/CXX to ccache-wrapped clang so the NSS build system
# picks it up transparently.
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends ccache \
    && apt-get autoremove -y && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

ENV CCACHE_DIR=/workspaces/nss-dev/.ccache \
    CCACHE_MAXSIZE=5G \
    CCACHE_COMPRESS=1 \
    CC="ccache clang" \
    CXX="ccache clang++"

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
RUN mkdir -p /workspaces/nss-dev /workspaces/nss-dev/nspr /workspaces/nss-dev/nss /workspaces/nss-dev/.ccache \
    && chown -R vscode:vscode /workspaces/nss-dev
