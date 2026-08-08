# syntax=docker/dockerfile:1
# DeOptiDownloader — containerized Web deployment.
#
# The Rust core is compiled to WASM (flutter_rust_bridge build-web) and the
# Flutter app is built for the web, then served by nginx. Because the WASM
# module uses threads/SharedArrayBuffer, nginx must emit COOP/COEP headers
# (see nginx.conf).

# ---------------------------------------------------------------------------
# Stage 1 — build the Flutter Web bundle.
# ---------------------------------------------------------------------------
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# Rust toolchain: nightly (FRB build-web defaults to nightly + -Z build-std),
# wasm32 target, rust-src component for build-std, plus wasm-pack and the
# wasm-bindgen CLI version that matches rust/Cargo.lock.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
      --profile minimal \
      --default-toolchain nightly \
      --target wasm32-unknown-unknown \
      --component rust-src
ENV PATH="/root/.cargo/bin:${PATH}"
RUN cargo install wasm-pack --locked \
 && cargo install wasm-bindgen-cli --locked --version 0.2.92

# 1) Manifests first for layer caching.
COPY pubspec.yaml pubspec.lock analysis_options.yaml flutter_rust_bridge.yaml ./
COPY rust/Cargo.toml rust/Cargo.lock ./rust/
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

# ---------------------------------------------------------------------------
# Stage 2 — serve with nginx.
# ---------------------------------------------------------------------------
FROM nginx:alpine AS serve
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1/ >/dev/null 2>&1 || exit 1
