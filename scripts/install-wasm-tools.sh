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

wasm_pack_archive="wasm-pack-v${wasm_pack_version}-x86_64-unknown-linux-musl.tar.gz"
wasm_pack_dir="wasm-pack-v${wasm_pack_version}-x86_64-unknown-linux-musl"
curl --fail --show-error --silent --location \
  --retry 5 --retry-all-errors \
  --output "${download_dir}/${wasm_pack_archive}" \
  "https://github.com/rustwasm/wasm-pack/releases/download/v${wasm_pack_version}/${wasm_pack_archive}"
echo "${wasm_pack_sha256}  ${download_dir}/${wasm_pack_archive}" | sha256sum --check --status
tar -xzf "${download_dir}/${wasm_pack_archive}" -C "${download_dir}"
install -m 0755 "${download_dir}/${wasm_pack_dir}/wasm-pack" "${bin_dir}/wasm-pack"

wasm_bindgen_archive="wasm-bindgen-${wasm_bindgen_version}-x86_64-unknown-linux-musl.tar.gz"
wasm_bindgen_dir="wasm-bindgen-${wasm_bindgen_version}-x86_64-unknown-linux-musl"
curl --fail --show-error --silent --location \
  --retry 5 --retry-all-errors \
  --output "${download_dir}/${wasm_bindgen_archive}" \
  "https://github.com/rustwasm/wasm-bindgen/releases/download/${wasm_bindgen_version}/${wasm_bindgen_archive}"
echo "${wasm_bindgen_sha256}  ${download_dir}/${wasm_bindgen_archive}" | sha256sum --check --status
tar -xzf "${download_dir}/${wasm_bindgen_archive}" -C "${download_dir}"
install -m 0755 "${download_dir}/${wasm_bindgen_dir}/wasm-bindgen" "${bin_dir}/wasm-bindgen"

test "$("${bin_dir}/wasm-pack" --version)" = "wasm-pack ${wasm_pack_version}"
test "$("${bin_dir}/wasm-bindgen" --version)" = "wasm-bindgen ${wasm_bindgen_version}"
