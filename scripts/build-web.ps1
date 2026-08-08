# DeOptiDownloader — build the Web/WASM bundle locally.
#
# Prerequisites (once):
#   rustup toolchain install nightly --target wasm32-unknown-unknown --component rust-src
#   cargo install wasm-pack --locked
#   cargo install wasm-bindgen-cli --locked --version 0.2.92  # match rust/Cargo.lock
#
# Then run:  scripts/build-web.ps1 [release]

param(
  [switch]$Release
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host '>> flutter pub get'
flutter pub get

Write-Host '>> flutter_rust_bridge build-web'
if ($Release) {
  dart run flutter_rust_bridge build-web --release --dart-root $root
} else {
  dart run flutter_rust_bridge build-web --dart-root $root
}

Write-Host '>> flutter build web'
if ($Release) {
  flutter build web --release
} else {
  flutter build web
}

Write-Host 'Done. Serve build/web with a COOP/COEP-enabled static server'
Write-Host '(e.g. `docker compose up` or the bundled nginx.conf).'
