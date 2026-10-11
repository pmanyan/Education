# ==========================================
# STAGE 1: Setup Tooling Environment
# ==========================================
FROM rust:1.85-slim AS toolchain-env

# Install system build utilities
RUN apt-get update && apt-get install -y curl git build-essential wget && apt-get clean

# FIX: Install a modern, pre-compiled version of binaryen (wasm-opt) that supports anyref
RUN wget "https://github.com" \
    && tar -xvzf binaryen-version_116-x86_64-linux.tar.gz \
    && mv binaryen-version_116/bin/wasm-opt /usr/local/bin/ \
    && rm -rf binaryen-version_116*

# Install specific tooling binary dependencies (Cached heavily by Render)
RUN cargo install wasm-bindgen-cli --version 0.2.105 --locked
RUN cargo install wasm-snip --locked

# Install the exact Nightly toolchain and source code modules requested by Scramjet
RUN rustup toolchain install nightly
RUN rustup component add rust-src --toolchain nightly


# ==========================================
# STAGE 2: App Builder (Isolating Package Changes)
# ==========================================
FROM node:24-slim AS builder

# Securely inherit Rust compiler binaries and tools from the toolchain environment stage
COPY --from=toolchain-env /usr/local/cargo /usr/local/cargo
COPY --from=toolchain-env /usr/local/rustup /usr/local/rustup
COPY --from=toolchain-env /usr/local/bin/wasm-opt /usr/local/bin/wasm-opt

ENV PATH="/usr/local/cargo/bin:${PATH}"
ENV RUSTUP_HOME=/usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo

# Ensure core base native compilations utilities exist in node stage
RUN apt-get update && apt-get install -y git build-essential && apt-get clean
RUN npm install -g pnpm

WORKDIR /app

# CACHE LAYER: Copy ONLY dependency definitions first
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages/core/package.json ./packages/core/
COPY patches ./patches

# Install Node dependencies (Will skip completely if locks/packages didn't change)
RUN pnpm install --frozen-lockfile

# Copy the rest of the application source code
COPY . .

# Execute compilation pipeline
RUN cd packages/core && pnpm rewriter:build
RUN pnpm build

# ==========================================
# STAGE 3: Slim Production Runtime
# ==========================================
FROM node:24-slim AS runner

WORKDIR /app
ENV NODE_ENV=production

# Install only production runner tool
RUN npm install -g pnpm

# Pull only the compiled /app output from builder, keeping the image small
COPY --from=builder /app /app

EXPOSE 4141

# Start the proxy app
CMD ["pnpm", "dev"]

