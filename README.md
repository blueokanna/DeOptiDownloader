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
  and a **track-then-decode** pipeline in Rust: after the first successful
  read the receiver remembers the symbol's bounding box and only searches a
  small region of interest around it, falling back to a full-frame scan only
  after consecutive misses. A scene-brightness swing (screen off, hand over
  the camera) invalidates the ROI immediately.
- **SIMD scan conversion** — raw camera planes (YUV Y plane on Android/iOS,
  BGRA on Windows/macOS) are converted to tight luma and box-downscaled to
  the 1280px scan bound *inside* the Rust worker with arch-dispatched SIMD
  (SSE2 on x86-64, NEON on ARMv8, scalar elsewhere incl. WASM). The Dart side
  never loops over pixels; each frame crosses the bridge exactly once.
- **Symbol rate & dwell, decoupled from the screen refresh** — the sender
  still repaints at the configured frame rate, but a *new QR symbol* is
  emitted at its own rate (default 8 symbols/s ≈ 125 ms dwell), optionally
  repeating the same symbol for N display periods. A 5–10 fps receiver camera
  gets several exposure-stable reads per QR instead of one blurry 16 ms frame.
- **Auto frame size** — instead of always packing near the Version-40
  ceiling (2331/2953 B), the sender's *Auto* mode scores candidate payloads
  (800/1200/1600/2000/2400 B) with `G(B) = B·p(B)/(t_display + t_decode)` and
  picks the best estimated goodput. The model is a documented heuristic, not
  a measured curve — the definitive per-device numbers still need a
  calibration run on the target phone.
- **Non-blocking native pipeline** — fountain/QR encoding and camera-frame QR
  decoding run on Rust bridge workers instead of Flutter's UI isolate. The
  receiver writes camera frames into a **single-slot "latest wins" buffer**
  (never queues), decodes at a bounded ~20 fps budget, runs a cheap
  protocol-admission gate (magic/length) before the fountain, and throttles
  UI notifications to ~5 Hz — stale frames are dropped, never copied.
- **Optional end-to-end encryption (deopti_transfer 0.1.2)** — XChaCha20-
  Poly1305 with a password-derived key, **and** judge-recoverable transfer
  (JRC): a sender commits against a designated judge's public key, so any
  camera sees only a hiding commitment + ciphertext while the judge alone
  recovers the file with the matching secret key. Both are opt-in and gated
  behind the `encryption` Cargo feature on every native build.
- **Material 3 design system** — bundled Noto Sans SC variable typography,
  six independent `ColorSpec` seed palettes, six `ColorStyle` choices backed
  by real `DynamicSchemeVariant` values, system/light/dark modes, and an
  **AMOLED Dark** pure-black surface policy. M3 shape and motion tokens apply
  consistently across the interface.
- **Wallpaper & blur** — an in-app background can be turned off, set to one of
  the bundled gradient wallpapers, or set to a custom photo from the gallery,
  with a draggable gaussian-blur slider (0–24 σ) that frosts the image behind
  the UI.
- **i18n (ARB → gen-l10n)** — official Flutter localization: `en` + `zh` ARB
  sources, runtime language switching (system/English/中文), and fully
  localized Material widgets via `flutter_localizations`.
- **Predictive back** — `android:enableOnBackInvokedCallback="true"` is set,
  so Android 13+ renders the predictive back gesture animation.
- **Multi-platform** — Android, iOS, Windows, macOS and Web support sending and
  receiving; Linux currently sends only, with browser receive as the fallback.
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
| Sender tuning (symbol rate / dwell / frame size) | ✅ defaults 60 fps, 8 symbols/s, 1 display period, **Auto** frame size; 4/8/15/30 symbols/s presets, 1–4 dwell periods, 500–2953 B manual range |
| **New:** password encryption    | ✅ XChaCha20-Poly1305 + Argon2id (opt-in)          |
| **New:** judge-recoverable JRC  | ✅ deopti_transfer 0.1.2 `pack_file_jrc` (opt-in)  |
| **New:** automatic re-lock      | ✅ stream-conflict auto reset in Rust              |
| **New:** session manifest QR    | ✅ `rustbinary`-encoded setup QR + receive preview |
| **New:** diagnostics self-test  | ✅ `runSelfTest()` + `jrcSelfTest()` (home → bug)  |
| **New:** Material 3 + responsive| ✅ bundled font, M3 tokens, adaptive layouts      |
| **New:** themes + wallpaper     | ✅ AMOLED Dark etc. + blur, custom photo           |
| **New:** i18n                   | ✅ official ARB/gen-l10n (en/zh)                   |

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
│  Rust core (rust/src)                                           │
│  api/transfer.rs — sessions, pack/unpack, manifest QR,          │
│                     symbol-rate presets, auto frame size        │
│  api/manifest.rs — rustbinary session-manifest codec            │
│  api/qr.rs       — QR encode (qrcodegen) + ROI-tracked decode   │
│  luma.rs         — SIMD luma + box downscale (SSE2/NEON/scalar) │
│  api/types.rs    — cross-boundary DTOs                          │
└──────────────┬───────────────────────────────┬─────────────────┘
               │                               │
      deopti_transfer                rustbinary (session manifest
      (LT fountain core, DCF3         wire codec) + qrcodegen + rxing
       container, crypto)
```

Receiver pipeline (each stage decoupled):

```
Camera listener ─put▶ LatestFrameSlot (cap. 1, never queues)
                       │ take latest
                       ▼
            QR worker (FRB thread): SIMD scan → ROI tracker → decode
                       │ bytes
                       ▼
            Protocol admission: magic "D1 0F" → fountain | manifest
                       │
                       ▼
            Fountain receiver (incremental peel, sub-ms)
                       │
                       ▼
            UI telemetry (throttled) / file assembly
```

The **cargo** crate is `rust_lib_scan_downloader`; the bridge glue lives in
`lib/src/rust/` (generated). Everything protocol-related lives in
`deopti_transfer`; `rustbinary` is genuinely used to encode the compact,
bounded session-manifest payload (see `rust/src/api/manifest.rs`); the app
layer only adapts them to the bridge.

## Performance and hardware acceleration

The sender repaints at the configured frame rate (60 fps by default), while a
**new QR symbol** is emitted at its own rate (default 8 symbols/s, presets
4/8/15/30) and can be repeated for N display periods (dwell). Each native QR
frame is generated asynchronously on a Rust worker; Flutter only publishes the
newest matrix, and `QrDisplay` submits all dark modules to the renderer in one
`drawRawPoints` batch without anti-aliasing or rebuilding the widget tree per
frame.

On Android, Flutter uses Impeller and the activity has hardware acceleration
enabled; CameraX renders its preview through a GPU-backed texture. GPU
acceleration therefore covers QR rasterization, composition and camera
preview. Fountain coding, QR construction and `rxing` recognition remain CPU
work on background Rust workers.

The **receiver scan path is SIMD-accelerated CPU work in Rust**:

1. The camera thread only writes the raw frame into a single-slot
   "latest wins" buffer — it never decodes, never loops over pixels.
2. A decode worker (FRB thread) takes the latest frame and calls one Rust
   entry point that (a) converts the raw plane to tight luma — Y plane
   passthrough on Android/iOS/HarmonyOS, SIMD BGRA→luma on Windows/macOS —
   and (b) box-downscales it to the 1280px scan bound with arch-dispatched
   SIMD (SSE2 / NEON / scalar-for-WASM). Integer-step SIMD covers exact-fit
   sources (720p/1440p/4K→1280); a fractional scalar pass keeps full module
   resolution for 1080p sources (1920→1280, not 960).
3. The ROI tracker only scans the last known symbol box (expanded 15%) for
   the following frames; full-frame finder-pattern searches happen on the
   first lock and again only after 3 consecutive ROI misses.
4. The decode budget is ~20 frames/s (50 ms minimum interval); a cheap
   protocol-admission gate (magic + length) runs before the fountain, and UI
   notifications are throttled to ~5 Hz. The fountain peel itself is
   incremental and sub-millisecond, so it never blocks the visual decode.

Measured guidance (release): `qrcodegen` encodes a Version-40 frame in ~3 ms
desktop release; `rxing` decodes a clean 640px fast-pass in ~3 ms. The
receiver is not decode-bound in practice — the per-frame FFI copy of the raw
plane is the remaining dominant cost, which the SIMD conversion keeps to a
single crossing per frame.

### Receiver tuning guide

There is no return channel, so the sender offers pragmatic presets instead of
an adaptive loop:

| Parameter | Default | Notes |
| --- | --- | --- |
| Screen refresh (fps) | 60 Hz | still renders every frame smoothly |
| QR symbol rate | 8 symbols/s | ≈125 ms dwell per QR; presets 4 / 8 / 15 / 30 |
| Dwell (repeat) | 1 display period | repeat the same seq 2–4 periods for an easier lock |
| Frame size | **Auto** | scores 800/1200/1600/2000/2400 B by estimated goodput |

The auto frame-size model `G(B) = B·p(B) / (t_display(B) + t_decode(B))`
combines a fixed symbol dwell, a module-area decoder-cost estimate and a
reliability roll-off that penalizes dense symbols — it deliberately stops
short of the Version-40 ceiling, because near-capacity QRs are denser and
decode less reliably from a phone camera. The constants are documented
engineering estimates (see `auto_frame_size_for` in `rust/src/api/transfer.rs`)
and should be validated with a calibration run on the target device; they are
not claimed as universal measurements.

## Appearance: themes, wallpaper & i18n

**Themes** (`lib/src/app/theme/app_themes.dart`). `ColorSpec` selects one of
Indigo `#3D5AFE`, Cyan `#006C7A`, Emerald `#006B57`, Violet `#7C4DFF`, Sunset
`#B33C16`, or Neutral `#60646C`. `ColorStyle` independently selects
`tonalSpot`, `expressive`, `fidelity`, `vibrant`, `neutral`, or `monochrome`;
each maps directly to Flutter's `DynamicSchemeVariant`. Theme brightness and
the AMOLED pure-black surface policy are separate settings. All settings
persist with `shared_preferences`.

**Wallpaper** (`lib/src/app/theme/wallpaper.dart`). Three kinds: *none* (no
image, no blur control), *bundled* (five gradient wallpapers in
`assets/images/wallpapers/`), and *custom* (a photo from the gallery, stored
in the app support dir on native / as a data URI on web). An active wallpaper
gets a **draggable gaussian-blur slider (0–24 σ)** rendered with
`ImageFilter.blur` behind the whole app; surfaces turn translucent
automatically so the image glows through while on-* colors stay readable.

**i18n** (`lib/l10n/*.arb`, generated by `flutter gen-l10n`). Official ARB →
`AppLocalizations` pipeline with `flutter_localizations`; `en` + `zh` sources
and a system/English/中文 runtime switch.

## Judge-recoverable transfer (JRC)

`deopti_transfer` 0.1.2 adds the JRC primitive: a sender commits a file
against a **designated judge's public key**; any camera that intercepts the
QR stream sees only a hiding commitment and ciphertext; only the judge,
holding the matching **secret key**, recovers the original file.

- **Sender**: enable *Judge-recoverable (JRC)* on the Send page and paste the
  judge's public key (64 hex chars), or generate a fresh judge keypair with
  the dice button. The packed `envelope` streams through the fountain
  unchanged.
- **Judge / receiver**: on the Receive page, when a JRC envelope arrives the
  app asks for the judge secret key — either type it or use the key saved in
  Settings. `unpack_file_jrc_ffi` verifies the binding + DCF3 digest before
  offering the file, so a wrong key is rejected.
- The end-to-end round trip is covered by `jrcSelfTest()` (Rust) and the
  Flutter test suite; the `encryption` Cargo feature is enabled for every
  native build via `rust/cargokit.yaml` (the Web build keeps it off because
  `getrandom` has no source on `wasm32-unknown-unknown`).

## Predictive back

`android:enableOnBackInvokedCallback="true"` is declared in
`AndroidManifest.xml`, so on Android 13+ the system predictive-back gesture
animation plays for the Flutter navigator (the app targets SDK 34+).

## Platform support

| Platform        | Send | Receive | Notes                                            |
| --------------- | :--: | :-----: | ------------------------------------------------ |
| Android         | ✅   | ✅      | CameraX; YUV420/NV21 luma                        |
| iOS             | ✅   | ✅      | AVFoundation; YUV420/BGRA8888                    |
| Windows         | ✅   | ✅      | `camera_windows`; BGRA8888                       |
| macOS           | ✅   | ✅      | AVFoundation; YUV420/BGRA8888                    |
| Linux           | ✅   | ❌²     | no camera backend is included                    |
| Web / WASM      | ✅   | ✅      | getUserMedia + canvas → Rust WASM decode         |
| Docker          | ✅   | ✅      | Rust `deopti-server` serves the Web build        |
| HarmonyOS Next  | —    | —       | adapter source exists; OHOS runner is not shipped|

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

### Android build requirements

The Android build is pinned to **AGP 8.13 + Gradle 8.14.3** (`android/settings.gradle.kts`
and `android/gradle/wrapper/gradle-wrapper.properties`). AGP 9's built-in Kotlin is
currently incompatible with this plugin mix — `file_picker` 11.x conditionally skips
the Kotlin Gradle Plugin under AGP 9 (expecting built-in Kotlin), while
`camera_android_camerax`, `share_plus`, `wakelock_plus` and `package_info_plus` still
require classic KGP — so the project stays on AGP 8.x where every plugin compiles
through classic KGP. `android/gradle.properties` also sets `kotlin.incremental=false`
to avoid a known Windows Kotlin incremental-cache failure, and
`rust_builder/cargokit/gradle/plugin.gradle` was patched to use Gradle's `ExecOperations`
(Gradle 9 removed `Project.exec(Closure)`). The application id is
`com.deopti.downloader`.

Release signing: the release APK is signed with the keystore described in the
untracked `android/key.properties` when it exists (`storeFile`, `storePassword`,
`keyAlias`, `keyPassword`). Without it, the release build falls back to the
debug key so the APK is always signed and installable (`adb install` works) —
never unsigned. For publishing to a store, generate a real keystore, point
`android/key.properties` at it and keep both files safe and untracked.

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

Three workflows ship in [.github/workflows](.github/workflows):

| Workflow | What it runs |
| --- | --- |
| `ci.yml` | Rust workspace `fmt --check` + `clippy -D warnings` (default **and** `encryption` features) + `test` (lib + server); Flutter `analyze` + `test` (native lib built first); a real `flutter_rust_bridge build-web` + `flutter build web` (bundle uploaded as artifact); `docker build` |
| `deploy-pages.yml` | Verifies GitHub Pages is enabled (auto-enables it via the API when missing, otherwise fails with precise instructions), builds the Web/WASM bundle and publishes it to GitHub Pages |
| `release.yml` | Builds every platform artifact and publishes a GitHub Release (see below) |

Every command in the workflows is the exact command developers run locally, so
a green pipeline is meaningful.

### Publishing a release

Push a `v*` tag (or run the workflow manually with **Actions → Release →
Run workflow**):

```bash
git tag v1.0.0          # or v1.0.0+7 to also set the Android/iOS build number
git push origin v1.0.0
```

The release workflow builds, then attaches to the Release:

| Platform | Artifact |
| --- | --- |
| Android | release APKs (arm64-v8a / armeabi-v7a / x86_64) + App Bundle (`.aab`) |
| Windows | x64 zip of `build/windows/x64/runner/Release` |
| Linux | x64 `tar.gz` of the release bundle |
| macOS | `.app` zip (ad-hoc signed) |
| iOS | unsigned `.app` zip (`--no-codesign`; sign & notarize before distribution) |
| Web | WASM + Flutter web bundle zip |
| Docker | `ghcr.io/<owner>/<repo>:v<version>` and `:latest` |

Version resolution: the tag (`v1.2.3` → `1.2.3`, `v1.2.3+45` → build `45`) is
used for tag pushes; a manual dispatch uses the `version` input (or the
`pubspec.yaml` version as a fallback) and creates a **draft** release for
review.

**Android signing**: configure the secrets `ANDROID_KEYSTORE_BASE64` (base64
of the `.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and
`ANDROID_KEY_PASSWORD` in *Settings → Secrets and variables → Actions* to sign
release APKs/AABs with your store key. Without them the Gradle fallback signs
with the debug key (installable, but not store-ready — a warning is printed).

## Docker

```bash
docker build -t deopti-downloader .
docker run --rm -p 8080:8080 deopti-downloader
# open http://localhost:8080
```

`Dockerfile` is multi-stage: it builds the Flutter Web bundle + Rust WASM,
compiles the std-only `deopti-server`, then serves the bundle with it — no
nginx, no third-party service.

The Flutter archive contains Git metadata owned by its publishing UID. The
image extracts it with `tar --no-same-owner` and registers exactly
`/opt/flutter` as a system `safe.directory`; this prevents Git's "dubious
ownership" check from aborting `flutter --version` while keeping the exception
scoped to the SDK directory.

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
  src/api/transfer.rs   # FRB: sessions, pack/unpack, manifest QR, self-test,
                        #      symbol-rate presets, auto frame size
  src/api/manifest.rs   # rustbinary session-manifest codec (bounded, versioned)
  src/api/qr.rs         # FRB: QR encode + ROI-tracked decode (tracker state)
  src/api/types.rs      # shared DTOs (incl. QrTrackerState / QrDecodeResult)
  src/luma.rs           # SIMD luma extraction + box downscale (SSE2/NEON/scalar)
  server/               # deopti-server: std-only static server (no nginx)
lib/
  main.dart             # bootstrap (Rust init is non-blocking, errors surfaced)
  src/app/              # MaterialApp + settings controller + wallpaper scope
  src/app/theme/        # app_themes (M3 registry), wallpaper + persistence
  src/app/widgets/      # ModeCard and shared M3 widgets
  src/l10n/             # ARB sources + generated AppLocalizations (gen-l10n)
  src/core/transfer/    # SenderController (symbol rate/dwell), ReceiverController
                        #   (latest-frame slot + pump + admission), payload
  src/core/camera/      # camera sources + raw-plane LumaFrame wrappers
  src/core/qr/          # QrPainter / QrDisplay
  src/core/services/    # FileService (io / web), judge_keys helper
  src/core/util/        # formatBytes, best-effort ScreenKeep
  src/pages/            # Home, Send, Receive, Settings (responsive, animated)
  src/rust/             # generated FRB glue (do not edit)
.github/workflows/      # ci.yml + deploy-pages.yml + release.yml
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
