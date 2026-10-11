# Multi-stage build to keep the final image clean
FROM node:24-slim AS builder

# Install system dependencies
RUN apt-get update && apt-get install -y curl git build-essential && apt-get clean

# Download and run the official rustup script safely from the correct script URL
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install WebAssembly tools required by Scramjet
RUN cargo install wasm-bindgen-cli
RUN apt-get install -y binaryen
RUN cargo install wasm-snip

# Set up pnpm
RUN npm install -g pnpm

WORKDIR /app

# Copy dependency configs, workspace maps, AND required engine patches
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

