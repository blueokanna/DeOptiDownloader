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
#
# The asset filename is passed verbatim and never derived from the version:
# wasm-pack archives keep the 'v' in the filename (wasm-pack-v0.15.0-...tar.gz)
# while wasm-bindgen archives drop it (wasm-bindgen-0.2.92-...tar.gz).
download_and_install() {
  local name="$1"
  local version="$2"
  local sha256="$3"
  local base_url="$4"
  local archive="$5"
  local archive_path="${download_dir}/${archive}"

  # Reuse an existing archive only when it already passes the pinned checksum;
  # a stale/corrupt file falls through to a fresh download.
  if [[ -f "${archive_path}" ]] && \
     echo "${sha256}  ${archive_path}" | sha256sum --check --status 2>/dev/null; then
    echo "==> Reusing cached ${archive}"
  else
    echo "==> Downloading ${archive}"
    curl --fail --show-error --silent --location \
      --connect-timeout 15 --max-time 180 \
      --retry 3 --retry-all-errors --retry-delay 2 \
      --output "${archive_path}" \
      "${base_url}/${archive}"
    echo "${sha256}  ${archive_path}" | sha256sum --check --status \
      || { echo "ERROR: sha256 mismatch for ${archive} — corrupted download or wrong pinned hash" >&2; exit 1; }
  fi

  tar -xzf "${archive_path}" -C "${download_dir}"

  # Locate the binary inside the archive instead of assuming its top-level
  # layout (which is not guaranteed to stay flat across releases).
  local bin_path
  bin_path="$(find "${download_dir}" -mindepth 1 -maxdepth 3 -type f -name "${name}" -print -quit)"
  if [[ -z "${bin_path}" || ! -x "${bin_path}" ]]; then
    echo "ERROR: ${name} binary not found in extracted archive" >&2
    exit 1
  fi
  install -m 0755 "${bin_path}" "${bin_dir}/${name}"
  echo "==> Installed ${name} ${version} -> ${bin_dir}/${name}"
}

# Canonical (post-move) repository URLs — the release assets live under the
# `wasm-bindgen` org now; the legacy `rustwasm/...` path only works via a
# redirect, which some runners handle less reliably.
#
# wasm-pack's asset filename carries the 'v' prefix from its tag, wasm-bindgen's
# does not — so each filename is spelled out explicitly below.
download_and_install wasm-pack "$wasm_pack_version" "$wasm_pack_sha256" \
  "https://github.com/wasm-bindgen/wasm-pack/releases/download/v${wasm_pack_version}" \
  "wasm-pack-v${wasm_pack_version}-x86_64-unknown-linux-musl.tar.gz"

download_and_install wasm-bindgen "$wasm_bindgen_version" "$wasm_bindgen_sha256" \
  "https://github.com/wasm-bindgen/wasm-bindgen/releases/download/${wasm_bindgen_version}" \
  "wasm-bindgen-${wasm_bindgen_version}-x86_64-unknown-linux-musl.tar.gz"

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
