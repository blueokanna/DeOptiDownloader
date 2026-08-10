#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 || -z "$1" || -z "$2" ]]; then
  echo "usage: $0 <bin-dir> <download-dir>" >&2
  exit 64
fi

readonly bin_dir="$1"
readonly download_dir="$2"
readonly wasm_pack_version='0.15.0'
readonly wasm_pack_sha256='c09f971ecaed9a2efc80fdcea7a00ef6b53c7fadc8c57d1f61b53a6aa66b668a'
readonly wasm_bindgen_version='0.2.92'
readonly wasm_bindgen_sha256='c6e43a3bf0be5231e0b72ea702f73b3f4f47c309037e8a332c5c2e41800ca934'

mkdir -p "${bin_dir}" "${download_dir}"

# Download, integrity-check and install one prebuilt x86_64-linux-musl tool.
# Each step fails loudly so a CI log points at the exact cause (download vs
# hash vs archive layout) instead of a bare "exit code: 1".
download_and_install() {
  local name="$1"
  local version="$2"
  local sha256="$3"
  local base_url="$4"

  local archive="${name}-${version}-x86_64-unknown-linux-musl.tar.gz"
  local dir="${name}-${version}-x86_64-unknown-linux-musl"

  echo "==> Downloading ${name} ${version}"
  curl --fail --show-error --silent --location \
    --connect-timeout 15 --max-time 180 \
    --retry 3 --retry-all-errors --retry-delay 2 \
    --output "${download_dir}/${archive}" \
    "${base_url}/${archive}"

  echo "${sha256}  ${download_dir}/${archive}" | sha256sum --check --status \
    || { echo "ERROR: sha256 mismatch for ${archive} — corrupted download or wrong hash" >&2; exit 1; }

  tar -xzf "${download_dir}/${archive}" -C "${download_dir}"
  if [[ ! -x "${download_dir}/${dir}/${name}" ]]; then
    echo "ERROR: ${name} binary not found in ${dir}" >&2
    exit 1
  fi
  install -m 0755 "${download_dir}/${dir}/${name}" "${bin_dir}/${name}"
  echo "==> Installed ${name} ${version} -> ${bin_dir}/${name}"
}

# Canonical (post-move) repository URLs — the release assets live under the
# `wasm-bindgen` org now; the legacy `rustwasm/...` path only works via a
# redirect, which some runners handle less reliably.
download_and_install wasm-pack "$wasm_pack_version" "$wasm_pack_sha256" \
  "https://github.com/wasm-bindgen/wasm-pack/releases/download/v${wasm_pack_version}"

download_and_install wasm-bindgen "$wasm_bindgen_version" "$wasm_bindgen_sha256" \
  "https://github.com/wasm-bindgen/wasm-bindgen/releases/download/${wasm_bindgen_version}"

# Verify the version prefix, not an exact string: `wasm-bindgen --version`
# appends the build's git commit hash, e.g. "wasm-bindgen 0.2.92 (2a4a49362)".
if ! "${bin_dir}/wasm-pack" --version | grep -Eq "^wasm-pack ${wasm_pack_version}([[:space:]]|$)"; then
  echo "ERROR: unexpected wasm-pack version: $("${bin_dir}/wasm-pack" --version)" >&2
  exit 1
fi
if ! "${bin_dir}/wasm-bindgen" --version | grep -Eq "^wasm-bindgen ${wasm_bindgen_version}([[:space:]]|$)"; then
  echo "ERROR: unexpected wasm-bindgen version: $("${bin_dir}/wasm-bindgen" --version)" >&2
  exit 1
fi
echo "==> wasm-pack ${wasm_pack_version} and wasm-bindgen ${wasm_bindgen_version} ready in ${bin_dir}"
