# syntax=docker/dockerfile:1
# DeOptiDownloader — containerized Web deployment served by the repository's
# own Rust static server (`rust/server`, std-only, no nginx, no third-party
# service).

# ---------------------------------------------------------------------------
# Stage 1 — build: Flutter Web bundle + Rust WASM + the deopti-server binary.
#
# Flutter is installed from the official release archive and pinned to the
# exact version the project is developed against (3.44.6 / Dart 3.12.2 — the
# same version CI uses, see .metadata). Prebuilt "flutter" Docker images are
# deliberately NOT used: ghcr.io/cirruslabs/flutter stopped being updated on
# 2026-05-01 and its `stable` tag ships Dart 3.12.0, which cannot resolve the
# committed pubspec.lock (its dependency graph requires `dart: >=3.12.2`).
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS build

# Flutter 3.44.6 (Dart 3.12.2) — must match CI's pinned version.
ENV FLUTTER_VERSION=3.44.6
ENV FLUTTER_ROOT=/opt/flutter
ENV PATH="${FLUTTER_ROOT}/bin:${PATH}"

WORKDIR /app

# Minimal system packages for `flutter build web` + the Rust toolchain.
# `clang`/`build-essential`/`pkg-config` are insurance: some build scripts in
# the dependency tree probe for a C compiler (e.g. the `cc` crate), and
# debian:bookworm-slim ships none by default — on the CI runner (ubuntu) they
# are present, so a missing compiler only surfaces in this container.
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      clang \
      curl \
      git \
      pkg-config \
      unzip \
      xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Rust toolchain: nightly (FRB build-web defaults to nightly + -Z build-std),
# plus prebuilt wasm-pack and the wasm-bindgen CLI version that matches
# rust/Cargo.lock.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
      --profile minimal \
      --default-toolchain nightly
ENV PATH="/root/.cargo/bin:${PATH}"
# `-Z build-std=std,panic_abort` REQUIRES the `rust-src` component, and
# wasm-pack requires the `wasm32-unknown-unknown` target. rustup's
# `--component`/`--target` flags on the initial install are unreliable across
# versions, so add them explicitly here and verify — otherwise cargo fails a
# few seconds into `flutter_rust_bridge build-web` with an unreadable
# "exit code: 255".
RUN rustup component add rust-src --toolchain nightly \
 && rustup target add wasm32-unknown-unknown --toolchain nightly \
 && rustup component list --toolchain nightly | grep -q rust-src \
 && rustup target list --installed | grep -q wasm32-unknown-unknown
COPY scripts/install-wasm-tools.sh /usr/local/src/install-wasm-tools.sh
RUN bash /usr/local/src/install-wasm-tools.sh /usr/local/bin /tmp/wasm-tools \
 && rm -rf /tmp/wasm-tools

# Fail fast: verify every tool `flutter_rust_bridge build-web` depends on
# actually executes on this base image. A missing/broken rustc, cargo,
# wasm-pack or wasm-bindgen would otherwise surface 20 minutes later as an
# unreadable "exit code: 255" at the build-web step.
RUN rustc --version \
 && cargo --version \
 && wasm-pack --version \
 && wasm-bindgen --version

# Install the pinned Flutter SDK from the official release archive (Dart
# 3.12.2, satisfies the locked `dart: >=3.12.2` requirement). Kept in its own
# layer so the ~600 MB download is cached across rebuilds.
RUN curl -fsSLo /tmp/flutter.tar.xz \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    && tar --no-same-owner -xJf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz \
    && git config --system --add safe.directory "${FLUTTER_ROOT}" \
    && flutter --version

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
#    NOTE: `wasm-opt` is disabled for this build via
#    `[package.metadata.wasm-pack.profile.release] wasm-opt = false` in
#    rust/Cargo.toml — the FRB build-web pipeline emits an atomics-featured
#    wasm that binaryen's wasm-opt cannot process (exit 255).
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

