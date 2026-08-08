# syntax=docker/dockerfile:1
# DeOptiDownloader — containerized Web deployment served by the repository's
# own Rust static server (`rust/server`, std-only, no nginx, no third-party
# service).

# ---------------------------------------------------------------------------
# Stage 1 — build: Flutter Web bundle + Rust WASM + the deopti-server binary.
# ---------------------------------------------------------------------------
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# Rust toolchain: nightly (FRB build-web defaults to nightly + -Z build-std),
# wasm32 target, rust-src component for build-std, plus prebuilt wasm-pack and
# the wasm-bindgen CLI version that matches rust/Cargo.lock.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
      --profile minimal \
      --default-toolchain nightly \
      --target wasm32-unknown-unknown \
      --component rust-src
ENV PATH="/root/.cargo/bin:${PATH}"
RUN curl -sSL https://github.com/rustwasm/wasm-pack/releases/download/v0.15.0/wasm-pack-v0.15.0-x86_64-unknown-linux-musl.tar.gz \
      | tar -xz -C /usr/local/bin --strip-components=1 wasm-pack-v0.15.0-x86_64-unknown-linux-musl/wasm-pack \
 && curl -sSL https://github.com/rustwasm/wasm-bindgen/releases/download/0.2.92/wasm-bindgen-0.2.92-x86_64-unknown-linux-musl.tar.gz \
      | tar -xz -C /usr/local/bin --strip-components=1 wasm-bindgen-0.2.92-x86_64-unknown-linux-musl/wasm-bindgen

# 1) Manifests first for layer caching.
COPY pubspec.yaml pubspec.lock analysis_options.yaml flutter_rust_bridge.yaml ./
COPY rust/Cargo.toml rust/Cargo.lock ./rust/
COPY rust/server/Cargo.toml ./rust/server/
COPY rust_builder/pubspec.yaml ./rust_builder/
RUN flutter pub get

# 2) Sources.
COPY lib ./lib
COPY rust ./rust
COPY rust_builder ./rust_builder
COPY web ./web
COPY assets ./assets

# 3) Build the Rust WASM module into web/pkg/ (bridge glue is committed).
RUN dart run flutter_rust_bridge build-web --release --dart-root /app

# 4) Build the Flutter Web bundle (dart2js + Rust WASM).
RUN flutter build web --release

# 5) Build the std-only static server (glibc, matches the runtime image).
RUN cargo build --release --manifest-path /app/rust/server/Cargo.toml

# ---------------------------------------------------------------------------
# Stage 2 — run: the repository's Rust server serves the bundle.
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS run
WORKDIR /srv
COPY --from=build /app/build/web /srv/web
COPY --from=build /app/rust/target/release/deopti-server /usr/local/bin/deopti-server
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD bash -c 'exec 3<>/dev/tcp/127.0.0.1/8080' || exit 1
CMD ["deopti-server", "--root", "/srv/web", "--port", "8080"]

