# Start directly with a modern Rust environment
FROM rust:1.85-slim AS rust-env

# Bring in Node.js 24 environment securely
FROM node:24-slim AS builder

# Copy Rust compiler binaries and tools over from our Rust base image
COPY --from=rust-env /usr/local/cargo /usr/local/cargo
COPY --from=rust-env /usr/local/rustup /usr/local/rustup
ENV PATH="/usr/local/cargo/bin:${PATH}"
ENV RUSTUP_HOME=/usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo

# Install system utilities
RUN apt-get update && apt-get install -y curl git build-essential binaryen && apt-get clean

# Force cargo to use historical locked dependency versions instead of fetching bleeding-edge updates
RUN cargo install wasm-bindgen-cli --version 0.2.105 --locked
RUN cargo install wasm-snip --locked

# Install the exact Nightly toolchain and source code modules requested by Scramjet
RUN rustup toolchain install nightly
RUN rustup component add rust-src --toolchain nightly

# Set up pnpm
RUN npm install -g pnpm

WORKDIR /app

# Copy dependency configs, workspace maps, and required engine patches
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages/core/package.json ./packages/core/
COPY patches ./patches

# Install Node dependencies with patches available
RUN pnpm install

# Copy the rest of the application source code
COPY . .

# Execute the compile order required by Scramjet
RUN cd packages/core && pnpm rewriter:build
RUN pnpm build

# Final production stage
FROM node:24-slim
RUN npm install -g pnpm
WORKDIR /app

COPY --from=builder /app /app

EXPOSE 4141

# Start the proxy app
CMD ["pnpm", "dev"]
