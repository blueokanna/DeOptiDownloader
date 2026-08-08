# DeOptiDownloader

**Fountain-coded QR file transfer over light — a Rust core + Flutter app.**

Send a file between two devices using nothing but a **screen and a camera**.
One device displays the file as an endless stream of animated QR codes; the
other points its camera at it and reconstructs the file. **No network path, no
pairing, no permissions beyond the camera.** The payload travels as light.

Rust 核心 + Flutter 跨端实现，支持发送/接收文件与文本片段。中文说明见
[README.zh-CN.md](README.zh-CN.md)。

---

## Highlights

- **Fountain coding (LT codes)** — the sender never repeats a frame: every QR
  is a fresh coded combination of the source blocks. The receiver collects any
  ~K·1.15 distinct frames, in any order, and decodes. **Dropped frames cost
  time, never correctness.**
- **Self-describing frames** — a 25-byte header carries session id, sequence,
  block count/size, total length and BLAKE3 integrity tags. No handshake: the
  receiver locks onto a stream mid-flight and re-locks automatically when the
  sender restarts.
- **DCF3 container** — filename, media type, optional gzip (only when it
  shrinks the payload) and a BLAKE3 digest of the original bytes; everything
  is verified before the file is offered.
- **Session manifest (built with `rustbinary`)** — before the data stream, the
  sender shows a small setup QR carrying the file name, size, block layout and
  session id. The receiver scans it and previews the incoming transfer *before
  the first data frame arrives*, then verifies the stream that locks on
  belongs to the same session. The compact, bounded payload is encoded with
  the `rustbinary` binary codec (see `rust/src/api/manifest.rs`).
- **QR layer tuned for streaming** — ECC level L, smallest fitting version,
  and a downscale-then-decode pipeline in Rust for fast, stable camera
  decoding.
- **Optional end-to-end encryption** — XChaCha20-Poly1305 with a
  password-derived key (opt-in; see below).
- **Material 3 design system** — Google Fonts (Noto Sans SC, bundled for
  offline use on every platform), full M3 color / shape / motion tokens, and
  adaptive responsive layouts for phones, tablets, desktops, Web and
  HarmonyOS windows.
- **Fully cross-platform** — Android, iOS, HarmonyOS Next, Windows, macOS,
  Linux, Web/WASM and Docker (containerized web).
- **CI-ready** — GitHub Actions runs Rust lint/tests, Flutter analyze/tests, a
  real Web/WASM build and a Docker build on every push (see
  [.github/workflows](.github/workflows)).

## Feature parity with the reference project

Everything from [bashalarmistalt/decimen-optical-transfer](
https://github.com/bashalarmistalt/decimen-optical-transfer) is implemented
and extended:

| Reference capability            | DeOptiDownloader                                   |
| ------------------------------- | -------------------------------------------------- |
| Send files (≤ 64 MB)            | ✅ `file_picker`, size-capped at 64 MB             |
| Send text snippets              | ✅ snippet dialog → `text/plain` container         |
| Fountain-coded QR stream        | ✅ Rust `deopti_transfer` + `qrcode`               |
| Camera → QR decode → file       | ✅ Rust `rxing` decode (native + WASM)             |
| SHA-256 verified before offer   | ✅ BLAKE3 digest verified by the container layer   |
| gzip only when it helps         | ✅ handled by `deopti_transfer::pack_file`         |
| Filename / media type preserved | ✅ DCF3 container                                  |
| Progress + “no signal” hint     | ✅ progress bar, receiver-lock line, hint card     |
| Keep-screen-on while streaming  | ✅ `wakelock_plus` (send + receive)                |
| Sender tuning (fps / frame size)| ✅ 10/15/20/24/30/60 fps, 500–2953 B frames       |
| **New:** password encryption    | ✅ XChaCha20-Poly1305 + Argon2id (opt-in)          |
| **New:** automatic re-lock      | ✅ stream-conflict auto reset in Rust              |
| **New:** session manifest QR    | ✅ `rustbinary`-encoded setup QR + receive preview |
| **New:** diagnostics self-test  | ✅ `runSelfTest()` in the app (home → bug icon)    |
| **New:** Material 3 + responsive| ✅ Google Fonts, M3 tokens, adaptive layouts       |

## Architecture

```
┌────────────────────────── Flutter UI ──────────────────────────┐
│  Home · Send · Receive   (Material 3, zh/en)                   │
│  SenderController / ReceiverController (frame loops, stats)    │
│  CameraFrameSource abstraction (plugin / getUserMedia)         │
│  QrDisplay (RLE painter, 60 fps) · FileService (io/web)        │
└──────────────┬───────────────────────────────┬─────────────────┘
               │ flutter_rust_bridge (FRB 2.12) │
┌──────────────▼───────────────────────────────▼─────────────────┐
│  Rust core (rust/src/api)                                       │
│  transfer.rs — sessions, pack/unpack, manifest QR, self-test    │
│  manifest.rs — rustbinary session-manifest codec                │
│  qr.rs       — QR encode (qrcode) + decode (rxing) + downscale  │
│  types.rs    — cross-boundary DTOs                              │
└──────────────┬───────────────────────────────┬─────────────────┘
               │                               │
      deopti_transfer                rustbinary (session manifest
      (LT fountain core, DCF3         wire codec) + qrcode + rxing
       container, crypto)
```

The **cargo** crate is `rust_lib_deopti_downloader`; the bridge glue lives in
`lib/src/rust/` (generated). Everything protocol-related lives in
`deopti_transfer`; `rustbinary` is genuinely used to encode the compact,
bounded session-manifest payload (see `rust/src/api/manifest.rs`); the app
layer only adapts them to the bridge.

## Platform support

| Platform        | Send | Receive | Notes                                            |
| --------------- | :--: | :-----: | ------------------------------------------------ |
| Android         | ✅   | ✅      | `camera` (CameraX) YUV420 image stream           |
| iOS             | ✅   | ✅      | `camera` (AVFoundation) YUV420 image stream      |
| HarmonyOS Next  | ✅   | ✅      | native `HarmonyCameraSource` (YUV420 + BGRA)     |
| Windows         | ✅   | ✅      | `camera_windows` backend                         |
| macOS           | ✅   | ✅      | `camera` (AVFoundation)                          |
| Linux           | ✅   | ⚠️²     | no federated camera backend yet                  |
| Web / WASM      | ✅   | ✅      | getUserMedia + canvas → Rust WASM decode         |
| Docker          | ✅   | ✅      | Rust `deopti-server` serves the Web build        |

² On Linux the receive page shows a clear message and suggests the browser
build (the Docker container or any browser).

## Quick start

```bash
# 1. Install the Rust bridge tooling
cargo install flutter_rust_bridge_codegen --locked --version 2.12.0

# 2. Regenerate the bridge after changing rust/src/api/*
flutter_rust_bridge_codegen generate

# 3. Run on a device / desktop
flutter pub get
flutter run            # pick a connected device
```

## Web / WASM

The Rust core is compiled to `wasm32-unknown-unknown` and loaded through the
browser (Flutter JavaScript UI + Rust WASM). The FRB bridge is generated in
**synchronous** mode (`default_dart_async: false` in `flutter_rust_bridge.yaml`),
so the app does not need SharedArrayBuffer or a worker pool — it runs on any
static host, including GitHub Pages.

```powershell
# One-time toolchain setup
rustup toolchain install nightly --target wasm32-unknown-unknown --component rust-src
cargo install wasm-pack --locked
cargo install wasm-bindgen-cli --locked --version 0.2.92   # must match rust/Cargo.lock

# Build
powershell -File scripts/build-web.ps1 -Release

# Serve with the repository's own Rust server (std-only, no nginx)
cargo build --release --manifest-path rust/server/Cargo.toml
./rust/target/release/deopti-server --root build/web --port 8080
# open http://localhost:8080
```

The Rust `deopti-server` (see next section) sends `Cross-Origin-Opener-Policy:
same-origin` and `Cross-Origin-Embedder-Policy: require-corp` so a future
threaded WASM build keeps working and SharedArrayBuffer stays available.
GitHub Pages works too (the `deploy-pages.yml` workflow), because the current
synchronous bridge does not require cross-origin isolation.

> Note: the app is **not** built with Flutter's experimental `--wasm`
> renderer — that mode is incompatible with the `dart:html` camera/file
> backends and the FRB runtime. The production Web build is dart2js + Rust
> WASM, which is fully supported.

## Serving the Web build (Rust, no nginx)

Deployment is served by the repository's own **Rust** static server
(`rust/server`, zero third-party dependencies, std only):

```bash
cargo build --release --manifest-path rust/server/Cargo.toml
./rust/target/release/deopti-server --root build/web --port 8080
```

The server sends COOP/COEP isolation headers, immutable caching for
content-hashed assets, ETag/304 revalidation, SPA fallback and strict
path-traversal protection. Options: `--root`, `--host`, `--port` (or the
`DEOPTI_ROOT` / `DEOPTI_HOST` / `DEOPTI_PORT` env vars).

## GitHub Actions

Two workflows ship in [.github/workflows](.github/workflows):

| Workflow | What it runs |
| --- | --- |
| `ci.yml` | Rust workspace `fmt --check` + `clippy -D warnings` + `test` (lib + server); Flutter `analyze` + `test` (native lib built first); a real `flutter_rust_bridge build-web` + `flutter build web` (bundle uploaded as artifact); `docker build` |
| `deploy-pages.yml` | Builds the Web/WASM bundle and publishes it to GitHub Pages (enable *Settings → Pages → Source: GitHub Actions*) |

Every command in the workflows is the exact command developers run locally, so
a green pipeline is meaningful.

## Docker

```bash
docker build -t deopti-downloader .
docker run --rm -p 8080:8080 deopti-downloader
# open http://localhost:8080
```

`Dockerfile` is multi-stage: it builds the Flutter Web bundle + Rust WASM,
compiles the std-only `deopti-server`, then serves the bundle with it — no
nginx, no third-party service.

## Encryption (opt-in)

Plain transfers are readable by any camera pointed at the screen. For
confidentiality, enable the Cargo feature on native targets:

```bash
# native builds (Android/iOS/desktop)
flutter_rust_bridge build --features encryption   # per-target, or
# web build with encryption
dart run flutter_rust_bridge build-web --release --dart-root . --cargo-build-args "--features encryption"
```

The sender picks a password, the receiver enters it once the container
arrives. The password is never transmitted; the wire carries only
XChaCha20-Poly1305 ciphertext (Argon2id key derivation). Web/WASM builds keep
encryption disabled by default because it requires `getrandom`, which is not
available on the default wasm target — the UI hides the password option when
the build lacks it (`encryptionSupported()`).

## Tests

```bash
cargo test --manifest-path rust/Cargo.toml   # QR codec + manifest + fountain self-test
flutter test                                  # host bridge + widget tests (incl. manifest round-trip)
flutter test integration_test -d <device>     # device E2E (self-test, QR round trip, boot)
```

## Project layout

```
rust/
  Cargo.toml            # workspace: FRB lib + `server/` member
  src/api/transfer.rs   # FRB: sessions, pack/unpack, manifest QR, self-test
  src/api/manifest.rs   # rustbinary session-manifest codec (bounded, versioned)
  src/api/qr.rs         # FRB: QR encode/decode, version table, downscale
  src/api/types.rs      # shared DTOs
  server/               # deopti-server: std-only static server (no nginx)
lib/
  main.dart             # bootstrap (Rust init is non-blocking, errors surfaced)
  src/app/              # MaterialApp, M3 theme (Google Fonts), responsive utils
  src/app/widgets/      # ModeCard and shared M3 widgets
  src/l10n/strings.dart # zh / en UI strings
  src/core/transfer/    # SenderController, ReceiverController, payload
  src/core/camera/      # CameraFrameSource + plugin / HarmonyOS / web backends
  src/core/qr/          # QrPainter / QrDisplay
  src/core/services/    # FileService (io / web)
  src/core/util/        # formatBytes, best-effort ScreenKeep
  src/pages/            # Home, Send, Receive (responsive, animated)
  src/rust/             # generated FRB glue (do not edit)
.github/workflows/      # ci.yml + deploy-pages.yml
Dockerfile · scripts/build-web.ps1
```

## Privacy

Transfers are **optical only** — no network path exists between the devices.
Without a password, everything on the sending screen is readable by any camera
pointed at it (that is the design: *no network*, not *confidentiality*). Enable
encryption when you need confidentiality.

## License

Apache-2.0. Core protocol and container format by the
[`deopti_transfer`](https://crates.io/crates/deopti_transfer) crate
(Apache-2.0); `qrcode`, `rxing` and `rustbinary` are Apache-2.0 / MIT as noted
by their respective authors.
