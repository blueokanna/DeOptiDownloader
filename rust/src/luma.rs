//! SIMD-accelerated luma extraction and box downscaling.
//!
//! Converts raw camera planes into the tight grayscale buffer the QR decoder
//! consumes, bounding the larger side to `max_dim` in the same pass. This is
//! the receiver's hottest per-frame cost on native devices, so it is written
//! with explicit SIMD kernels and a scalar reference path.
//!
//! Runtime dispatch:
//! - `x86_64`   → SSE2 (baseline on every x86-64 CPU; no feature probing)
//! - `aarch64`  → NEON (baseline on ARMv8)
//! - otherwise  → scalar (including `wasm32-unknown-unknown`)
//!
//! Every SIMD kernel has an equivalent scalar path and the unit tests compare
//! them on randomized input, so a fast path can never silently diverge.
//!
//! Frame-buffer policy: each call produces exactly one fresh buffer (the
//! decimated scan frame). The caller (the receiver loop) owns that buffer and
//! hands it to the decoder; no per-frame intermediate is allocated on the
//! Dart side, and the box filter is computed in one pass here.

/// A tight row-major grayscale (luma8) frame ready for the QR decoder.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GrayFrame {
    pub data: Vec<u8>,
    pub width: u32,
    pub height: u32,
}

impl GrayFrame {
    pub fn new(data: Vec<u8>, width: u32, height: u32) -> Self {
        Self {
            data,
            width,
            height,
        }
    }

    /// Box-average downscale is idempotent on the scan frame: the mean of the
    /// scan frame is a cheap, honest proxy for scene brightness (used by the
    /// QR tracker to detect "screen switched off / scene changed").
    pub fn mean_luma(&self) -> u8 {
        mean_luma(&self.data)
    }
}

/// Mean luma of a grayscale buffer (chunked u64 sum; never overflows).
pub fn mean_luma(data: &[u8]) -> u8 {
    let n = data.len();
    if n == 0 {
        return 0;
    }
    let mut sum: u64 = 0;
    for chunk in data.chunks(1 << 16) {
        let mut s: u64 = 0;
        for &b in chunk {
            s += b as u64;
        }
        sum += s;
    }
    (sum / n as u64) as u8
}

/// Integer decimation step so the larger side stays `<= max_dim` (min 1).
#[inline]
pub fn decimation_step(width: u32, height: u32, max_dim: u32) -> u32 {
    let max_side = width.max(height);
    if max_side <= max_dim || max_dim == 0 {
        1
    } else {
        max_side.div_ceil(max_dim)
    }
}

/// Whether an integer-step decimation lands exactly on `max_dim`.
///
/// When `max_side % max_dim == 0` the integer-step SIMD box filter keeps the
/// full scan resolution (e.g. 3840→1280, 2560→1280). Otherwise a fractional
/// scalar pass is used instead so a 1080p source (1920×1080) still resolves to
/// 1280×720 — a plain integer step would land on 960×540 and lose ~44% of the
/// module resolution of dense symbols.
#[inline]
pub fn integer_fit(width: u32, height: u32, max_dim: u32) -> bool {
    let max_side = width.max(height);
    if max_side <= max_dim || max_dim == 0 {
        return true;
    }
    max_side.is_multiple_of(max_dim)
}

/// Whether `raw` has enough bytes for a `width x height` plane with the given
/// row stride and pixel stride (mirrors the Dart-side guard in the old
/// decimation path).
#[inline]
pub fn yplane_len_ok(raw_len: usize, width: u32, height: u32, row_stride: u32, pixel_stride: u32) -> bool {
    if width == 0 || height == 0 || row_stride == 0 || pixel_stride == 0 {
        return false;
    }
    let required = (height - 1) as u64 * row_stride as u64
        + (width - 1) as u64 * pixel_stride as u64
        + 1;
    raw_len as u64 >= required
}

#[inline]
pub fn bgra_len_ok(raw_len: usize, width: u32, height: u32, row_stride: u32) -> bool {
    if width == 0 || height == 0 || row_stride == 0 || row_stride < width * 4 {
        return false;
    }
    let required = (height - 1) as u64 * row_stride as u64 + width as u64 * 4;
    raw_len as u64 >= required
}

// ---------------------------------------------------------------------------
// Y-plane (YUV420 / NV21) → scan-space grayscale
// ---------------------------------------------------------------------------

/// Extract the luminance plane of a YUV camera frame into a tight grayscale
/// frame whose larger side is `<= max_dim`.
///
/// The Y plane is already luma, so this is a copy + (optional) box
/// downscale — no colour math, which is why Android/iOS can feed this path
/// directly from the camera's Y plane.
pub fn yplane_to_gray(
    raw: &[u8],
    width: u32,
    height: u32,
    row_stride: u32,
    pixel_stride: u32,
    max_dim: u32,
) -> Option<GrayFrame> {
    if !yplane_len_ok(raw.len(), width, height, row_stride, pixel_stride) {
        return None;
    }
    let step = decimation_step(width, height, max_dim);
    let out_w = width.div_ceil(step);
    let out_h = height.div_ceil(step);

    if step == 1 {
        // No decimation: just strip the row padding (and, if needed, sample
        // at the pixel stride).
        return Some(strip_yplane(raw, width, height, row_stride, pixel_stride));
    }

    if !integer_fit(width, height, max_dim) {
        // 1080p-style ratios: an integer step would land well below max_dim
        // and destroy module detail. Strip the padding first, then use the
        // fractional scalar box filter (matches the pre-SIMD quality).
        let tight = strip_yplane(raw, width, height, row_stride, pixel_stride);
        return fractional_downscale(&tight.data, width, height, max_dim);
    }

    // Decimation: two-pass separable box filter (horizontal then vertical).
    let tmp = box_horizontal_yplane(raw, width, height, row_stride as usize, pixel_stride as usize, step);
    let data = box_vertical(&tmp, height, out_h, out_w, step);
    Some(GrayFrame::new(data, out_w, out_h))
}

// ---------------------------------------------------------------------------
// BGRA8888 → scan-space grayscale
// ---------------------------------------------------------------------------

/// Convert a packed BGRA8888 camera frame to tight luma, bounding the larger
/// side to `max_dim`. This is the Windows/macOS (and some HarmonyOS) path,
/// where the camera cannot deliver a Y plane.
pub fn bgra_to_gray(
    raw: &[u8],
    width: u32,
    height: u32,
    row_stride: u32,
    max_dim: u32,
) -> Option<GrayFrame> {
    if !bgra_len_ok(raw.len(), width, height, row_stride) {
        return None;
    }
    let step = decimation_step(width, height, max_dim);
    let out_w = width.div_ceil(step);
    let out_h = height.div_ceil(step);

    if step == 1 {
        let mut data = Vec::with_capacity((width as usize) * (height as usize));
        for y in 0..height {
            let base = y as usize * row_stride as usize;
            let row = &raw[base..base + width as usize * 4];
            let start = data.len();
            data.resize(start + width as usize, 0);
            bgra_row_to_luma(row, &mut data[start..]);
        }
        return Some(GrayFrame::new(data, width, height));
    }

    // Convert the full frame once, then box-decimate the tight luma.
    let mut full = Vec::with_capacity((width as usize) * (height as usize));
    for y in 0..height {
        let base = y as usize * row_stride as usize;
        let row = &raw[base..base + width as usize * 4];
        let start = full.len();
        full.resize(start + width as usize, 0);
        bgra_row_to_luma(row, &mut full[start..]);
    }
    if !integer_fit(width, height, max_dim) {
        return fractional_downscale(&full, width, height, max_dim);
    }
    let tmp = box_horizontal_tight(&full, width, height, step);
    let data = box_vertical(&tmp, height, out_h, out_w, step);
    Some(GrayFrame::new(data, out_w, out_h))
}

// ---------------------------------------------------------------------------
// Tight grayscale → scan-space grayscale (used by the web path + ROI)
// ---------------------------------------------------------------------------

/// Box-downscale an already-tight grayscale buffer; returns a copy when it is
/// already `<= max_dim`.
pub fn downscale_gray(data: &[u8], width: u32, height: u32, max_dim: u32) -> Option<GrayFrame> {
    if width == 0 || height == 0 || data.len() != (width as u64 * height as u64) as usize {
        return None;
    }
    let step = decimation_step(width, height, max_dim);
    if step == 1 {
        return Some(GrayFrame::new(data.to_vec(), width, height));
    }
    if !integer_fit(width, height, max_dim) {
        return fractional_downscale(data, width, height, max_dim);
    }
    let out_w = width.div_ceil(step);
    let out_h = height.div_ceil(step);
    let tmp = box_horizontal_tight(data, width, height, step);
    let out = box_vertical(&tmp, height, out_h, out_w, step);
    Some(GrayFrame::new(out, out_w, out_h))
}

/// Copy a Y plane into a tight grayscale buffer, handling row padding and an
/// optional pixel stride (interleaved Y is rare; sampling at the stride is
/// the correct luma extraction in that case).
fn strip_yplane(
    raw: &[u8],
    width: u32,
    height: u32,
    row_stride: u32,
    pixel_stride: u32,
) -> GrayFrame {
    let mut data = Vec::with_capacity((width as usize) * (height as usize));
    if pixel_stride == 1 {
        if row_stride == width {
            data.extend_from_slice(raw);
        } else {
            for y in 0..height {
                let base = y as usize * row_stride as usize;
                data.extend_from_slice(&raw[base..base + width as usize]);
            }
        }
    } else {
        let ps = pixel_stride as usize;
        for y in 0..height {
            let base = y as usize * row_stride as usize;
            for x in 0..width as usize {
                data.push(raw[base + x * ps]);
            }
        }
    }
    GrayFrame::new(data, width, height)
}

/// Fractional box downscale: each output pixel averages its exact source
/// footprint (window sizes vary by one pixel). This is the reference-quality
/// path for ratios like 1920→1280 where an integer step would land on 960.
fn fractional_downscale(data: &[u8], width: u32, height: u32, max_dim: u32) -> Option<GrayFrame> {
    let max_side = width.max(height);
    if max_side <= max_dim || max_dim == 0 {
        return Some(GrayFrame::new(data.to_vec(), width, height));
    }
    let scale = max_side as f64 / max_dim as f64;
    let nw = ((width as f64 / scale).round() as u32).max(1);
    let nh = ((height as f64 / scale).round() as u32).max(1);
    let mut out = Vec::with_capacity((nw * nh) as usize);
    for y in 0..nh {
        let y0 = (y as u64 * height as u64 / nh as u64) as usize;
        let y1 = (((y as u64 + 1) * height as u64 / nh as u64).max(y as u64 + 1)) as usize;
        for x in 0..nw {
            let x0 = (x as u64 * width as u64 / nw as u64) as usize;
            let x1 = (((x as u64 + 1) * width as u64 / nw as u64).max(x as u64 + 1)) as usize;
            let mut sum = 0u32;
            let mut count = 0u32;
            for row in y0..y1 {
                let base = row * width as usize;
                for col in x0..x1 {
                    sum += data[base + col] as u32;
                    count += 1;
                }
            }
            out.push((sum / count.max(1)) as u8);
        }
    }
    Some(GrayFrame::new(out, nw, nh))
}

// ---------------------------------------------------------------------------
// Box filter kernels
// ---------------------------------------------------------------------------

/// Horizontal box pass over a tight gray row (pixel_stride == 1).
fn box_horizontal_tight(src: &[u8], width: u32, height: u32, step: u32) -> Vec<u8> {
    let w = width as usize;
    let h = height as usize;
    let s = step as usize;
    let ow = w.div_ceil(s);
    let mut out = vec![0u8; h * ow];
    for y in 0..h {
        let row = &src[y * w..y * w + w];
        let o = &mut out[y * ow..y * ow + ow];
        box_horizontal_row_dispatch(row, w, s, o);
    }
    out
}

/// Horizontal box pass over a Y plane with padding / pixel stride.
fn box_horizontal_yplane(
    raw: &[u8],
    width: u32,
    height: u32,
    row_stride: usize,
    pixel_stride: usize,
    step: u32,
) -> Vec<u8> {
    let w = width as usize;
    let h = height as usize;
    let s = step as usize;
    let ow = w.div_ceil(s);
    let mut out = vec![0u8; h * ow];
    if pixel_stride == 1 {
        for y in 0..h {
            let row = &raw[y * row_stride..y * row_stride + w];
            let o = &mut out[y * ow..y * ow + ow];
            box_horizontal_row_dispatch(row, w, s, o);
        }
    } else {
        // Interleaved Y (rare): sample at the pixel stride, scalar only.
        for y in 0..h {
            let base = y * row_stride;
            let o = &mut out[y * ow..y * ow + ow];
            for (c, slot) in o.iter_mut().enumerate() {
                let start = c * s * pixel_stride;
                let end = ((c + 1) * s).min(w) * pixel_stride;
                let mut sum = 0u32;
                let mut n = 0u32;
                let mut i = start;
                while i < end {
                    sum += raw[base + i] as u32;
                    i += pixel_stride;
                    n += 1;
                }
                let n = n.max(1);
                *slot = ((sum + n / 2) / n) as u8;
            }
        }
    }
    out
}

/// One-row horizontal box; dispatches to the arch SIMD kernel when safe.
#[inline]
fn box_horizontal_row_dispatch(row: &[u8], w: usize, step: usize, out: &mut [u8]) {
    #[cfg(target_arch = "x86_64")]
    {
        // SAFETY: buffer lengths are validated by the callers.
        unsafe { sse2::box_row(row, w, step, out) };
    }
    #[cfg(target_arch = "aarch64")]
    {
        // SAFETY: buffer lengths are validated by the callers.
        unsafe { neon::box_row(row, w, step, out) };
    }
    #[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
    box_row_scalar(row, w, step, out);
}

/// Vertical box pass: average `step` rows of `tmp` into `out`.
fn box_vertical(tmp: &[u8], height: u32, out_h: u32, out_w: u32, step: u32) -> Vec<u8> {
    let h = height as usize;
    let ow = out_w as usize;
    let s = step as usize;
    let oh = out_h as usize;
    let mut out = vec![0u8; oh * ow];
    for r in 0..oh {
        let row_start = r * s;
        let n = s.min(h.saturating_sub(row_start));
        if n == 0 {
            continue;
        }
        let o = &mut out[r * ow..r * ow + ow];
        box_columns_dispatch(tmp, n, ow, o);
    }
    out
}

#[inline]
fn box_columns_dispatch(tmp: &[u8], n: usize, ow: usize, out: &mut [u8]) {
    #[cfg(target_arch = "x86_64")]
    {
        // SAFETY: `tmp` has at least n*ow bytes and `out` has ow bytes.
        unsafe { sse2::box_columns(tmp, n, ow, out) };
    }
    #[cfg(target_arch = "aarch64")]
    {
        // SAFETY: `tmp` has at least n*ow bytes and `out` has ow bytes.
        unsafe { neon::box_columns(tmp, n, ow, out) };
    }
    #[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
    box_columns_scalar(tmp, n, ow, out);
}

/// One row of BGRA → luma; dispatches to the arch SIMD kernel.
#[inline]
fn bgra_row_to_luma(row: &[u8], out: &mut [u8]) {
    #[cfg(target_arch = "x86_64")]
    {
        // SAFETY: `row` has 4*out.len() bytes and `out` has out.len() bytes.
        unsafe { sse2::bgra_row(row, out) };
    }
    #[cfg(target_arch = "aarch64")]
    {
        // SAFETY: `row` has 4*out.len() bytes and `out` has out.len() bytes.
        unsafe { neon::bgra_row(row, out) };
    }
    #[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
    bgra_row_scalar(row, out);
}

// ---------------------------------------------------------------------------
// Scalar reference kernels
// ---------------------------------------------------------------------------

#[inline]
fn box_row_scalar(row: &[u8], w: usize, step: usize, out: &mut [u8]) {
    for (oc, slot) in out.iter_mut().enumerate() {
        let start = oc * step;
        let end = (start + step).min(w);
        let n = end - start;
        if n == 0 {
            *slot = 0;
            continue;
        }
        let mut sum = 0u32;
        for &b in &row[start..end] {
            sum += b as u32;
        }
        *slot = ((sum + n as u32 / 2) / n as u32) as u8;
    }
}

// On x86_64 / aarch64 the scalar kernels are the SIMD *reference* (used by
// tests and by the scalar fallback on other targets like wasm32), so they are
// legitimately unused in a plain release build on those arches.
#[cfg_attr(any(target_arch = "x86_64", target_arch = "aarch64"), allow(dead_code))]
#[inline]
fn box_columns_scalar(tmp: &[u8], n: usize, ow: usize, out: &mut [u8]) {
    for (c, slot) in out.iter_mut().enumerate() {
        let mut sum = 0u32;
        for r in 0..n {
            sum += tmp[r * ow + c] as u32;
        }
        *slot = ((sum + n as u32 / 2) / n as u32) as u8;
    }
}

#[cfg_attr(any(target_arch = "x86_64", target_arch = "aarch64"), allow(dead_code))]
#[inline]
fn bgra_row_scalar(row: &[u8], out: &mut [u8]) {
    for (i, px) in row.chunks_exact(4).enumerate() {
        let blue = px[0] as u32;
        let green = px[1] as u32;
        let red = px[2] as u32;
        out[i] = ((77 * red + 150 * green + 29 * blue) >> 8) as u8;
    }
}

// ---------------------------------------------------------------------------
// x86_64 SSE2 kernels (baseline on x86-64)
// ---------------------------------------------------------------------------

#[cfg(target_arch = "x86_64")]
mod sse2 {
    use std::arch::x86_64::*;

    /// Average `step`-wide windows of one tight row.
    ///
    /// SIMD fast path: for a full window of `step <= 8` bytes with 16 bytes
    /// available after its start, load 16 bytes, mask the first `step` lanes
    /// and sum them with `_mm_sad_epu8` (which sums the 8 low bytes into one
    /// u16 accumulator). Windows that are partial, near the row end, or with
    /// `step > 8` fall back to scalar.
    ///
    /// # Safety
    /// `row.len() >= w`, `out.len() == ceil(w / step)`.
    pub unsafe fn box_row(row: &[u8], w: usize, step: usize, out: &mut [u8]) {
        if step <= 8 && w >= 16 {
            let mask = mask_keep_first(step);
            for (oc, slot) in out.iter_mut().enumerate() {
                let start = oc * step;
                let end = (start + step).min(w);
                if end - start == step && start + 16 <= row.len() {
                    let v = _mm_loadu_si128(row.as_ptr().add(start) as *const __m128i);
                    let kept = _mm_and_si128(v, mask);
                    let s = _mm_sad_epu8(kept, _mm_setzero_si128());
                    let lanes: [u16; 8] = std::mem::transmute(s);
                    let sum = lanes[0] as u32;
                    *slot = ((sum + step as u32 / 2) / step as u32) as u8;
                } else {
                    let n = end - start;
                    if n == 0 {
                        *slot = 0;
                        continue;
                    }
                    let mut sum = 0u32;
                    for &b in &row[start..end] {
                        sum += b as u32;
                    }
                    *slot = ((sum + n as u32 / 2) / n as u32) as u8;
                }
            }
            return;
        }
        super::box_row_scalar(row, w, step, out);
    }

    /// Average `n` consecutive rows (each `ow` wide) into one output row.
    ///
    /// # Safety
    /// `tmp.len() >= n * ow`, `out.len() == ow`.
    pub unsafe fn box_columns(tmp: &[u8], n: usize, ow: usize, out: &mut [u8]) {
        let mut oc = 0;
        while oc + 8 <= ow {
            let mut acc = _mm_setzero_si128();
            for r in 0..n {
                let v8 = _mm_loadl_epi64(tmp.as_ptr().add(r * ow + oc) as *const __m128i);
                let lo = _mm_unpacklo_epi8(v8, _mm_setzero_si128());
                acc = _mm_add_epi16(acc, lo);
            }
            let lanes: [u16; 8] = std::mem::transmute(acc);
            for (j, lane) in lanes.iter().enumerate() {
                out[oc + j] = ((*lane as u32 + n as u32 / 2) / n as u32) as u8;
            }
            oc += 8;
        }
        for c in oc..ow {
            let mut sum = 0u32;
            for r in 0..n {
                sum += tmp[r * ow + c] as u32;
            }
            out[c] = ((sum + n as u32 / 2) / n as u32) as u8;
        }
    }

    /// BGRA8888 row → luma (Rec.601 weights: 77 R + 150 G + 29 B, >> 8).
    ///
    /// # Safety
    /// `row.len() == 4 * out.len()`.
    pub unsafe fn bgra_row(row: &[u8], out: &mut [u8]) {
        let zero = _mm_setzero_si128();
        // Coeffs aligned to [B, G, R, A] per 64-bit lane (A is dropped):
        // lane0 = 0 (the shifted-in zero), lane1 = 29 (B), lane2 = 150 (G),
        // lane3 = 77 (R). `_mm_set_epi16` lists the highest lane first.
        let coef = _mm_set_epi16(77, 150, 29, 0, 77, 150, 29, 0);
        let mut i = 0usize;
        while i + 16 <= row.len() {
            let v = _mm_loadu_si128(row.as_ptr().add(i) as *const __m128i);
            let lo = _mm_unpacklo_epi8(v, zero); // [B0,G0,R0,A0,B1,G1,R1,A1]
            let hi = _mm_unpackhi_epi8(v, zero); // [B2,G2,R2,A2,B3,G3,R3,A3]
            let l0 = luma_quad(lo, coef);
            let l1 = luma_quad(hi, coef);
            let mut buf = [0u8; 16];
            _mm_storeu_si128(buf.as_mut_ptr() as *mut __m128i, l0);
            out[i / 4] = buf[0];
            out[i / 4 + 1] = buf[2];
            _mm_storeu_si128(buf.as_mut_ptr() as *mut __m128i, l1);
            out[i / 4 + 2] = buf[0];
            out[i / 4 + 3] = buf[2];
            i += 16;
        }
        // Tail scalar.
        for (idx, px) in row[i..].chunks_exact(4).enumerate() {
            let (b, g, r) = (px[0] as u32, px[1] as u32, px[2] as u32);
            out[i / 4 + idx] = ((77 * r + 150 * g + 29 * b) >> 8) as u8;
        }
    }

    /// Luma of two BGRA pixels packed as u16 lanes [B,G,R,A,B,G,R,A].
    #[inline]
    unsafe fn luma_quad(u: __m128i, coef: __m128i) -> __m128i {
        // Shift each 64-bit lane LEFT by 16 bits → [0,B,G,R, 0,B,G,R].
        let s = _mm_slli_epi64(u, 16);
        // madd pairs (0,1) and (2,3): m0 = 29B, m1 = 150G + 77R.
        let m = _mm_madd_epi16(s, coef);
        // Horizontal add of adjacent i32 lanes: lane0 = m0 + m1 = luma.
        let t = _mm_shuffle_epi32(m, 0b10_11_00_01);
        let l = _mm_add_epi32(m, t);
        let lr = _mm_srai_epi32(l, 8);
        let p = _mm_packs_epi32(lr, lr); // i16 [l0,l0,l1,l1,...]
        _mm_packus_epi16(p, p) // u8  [l0,l0,l1,l1,...]
    }

    #[inline]
    unsafe fn mask_keep_first(n: usize) -> __m128i {
        let mut bytes = [0u8; 16];
        for b in bytes.iter_mut().take(n.min(16)) {
            *b = 0xFF;
        }
        _mm_loadu_si128(bytes.as_ptr() as *const __m128i)
    }
}

// ---------------------------------------------------------------------------
// aarch64 NEON kernels (baseline on ARMv8)
// ---------------------------------------------------------------------------

#[cfg(target_arch = "aarch64")]
mod neon {
    use std::arch::aarch64::*;

    /// Average `step`-wide windows of one tight row.
    ///
    /// # Safety
    /// `row.len() >= w`, `out.len() == ceil(w / step)`.
    pub unsafe fn box_row(row: &[u8], w: usize, step: usize, out: &mut [u8]) {
        if step <= 8 && w >= 16 {
            // Keep only the first `step` bytes of each 16-byte load; the rest
            // is masked to zero so the lane sum equals the window sum.
            let mask = vld1q_u8(MASK_TABLE[step].as_ptr());
            for (oc, slot) in out.iter_mut().enumerate() {
                let start = oc * step;
                let end = (start + step).min(w);
                if end - start == step && start + 16 <= row.len() {
                    let v = vld1q_u8(row.as_ptr().add(start));
                    let kept = vandq_u8(v, mask);
                    // vaddlvq_u8 reduces the 16 lanes to a scalar u16; the
                    // masked-out lanes are zero so this is the window sum.
                    let total = vaddlvq_u8(kept) as u32;
                    *slot = ((total + step as u32 / 2) / step as u32) as u8;
                } else {
                    let n = end - start;
                    if n == 0 {
                        *slot = 0;
                        continue;
                    }
                    let mut sum = 0u32;
                    for &b in &row[start..end] {
                        sum += b as u32;
                    }
                    *slot = ((sum + n as u32 / 2) / n as u32) as u8;
                }
            }
            return;
        }
        super::box_row_scalar(row, w, step, out);
    }

    /// Average `n` consecutive rows (each `ow` wide) into one output row.
    ///
    /// # Safety
    /// `tmp.len() >= n * ow`, `out.len() == ow`.
    pub unsafe fn box_columns(tmp: &[u8], n: usize, ow: usize, out: &mut [u8]) {
        let mut oc = 0;
        while oc + 8 <= ow {
            let mut acc = vdupq_n_u16(0);
            for r in 0..n {
                let v8 = vld1_u8(tmp.as_ptr().add(r * ow + oc));
                let w8 = vmovl_u8(v8); // 8 u16
                acc = vaddq_u16(acc, w8);
            }
            let lanes: [u16; 8] = std::mem::transmute(acc);
            for (j, lane) in lanes.iter().enumerate() {
                out[oc + j] = ((*lane as u32 + n as u32 / 2) / n as u32) as u8;
            }
            oc += 8;
        }
        for c in oc..ow {
            let mut sum = 0u32;
            for r in 0..n {
                sum += tmp[r * ow + c] as u32;
            }
            out[c] = ((sum + n as u32 / 2) / n as u32) as u8;
        }
    }

    /// BGRA8888 row → luma (Rec.601 weights: 77 R + 150 G + 29 B, >> 8).
    ///
    /// # Safety
    /// `row.len() == 4 * out.len()`.
    pub unsafe fn bgra_row(row: &[u8], out: &mut [u8]) {
        let mut i = 0usize;
        while i + 16 <= row.len() {
            let v = vld1q_u8(row.as_ptr().add(i));
            let lo = vmovl_u8(vget_low_u8(v));  // [B0,G0,R0,A0,B1,G1,R1,A1]
            let hi = vmovl_u8(vget_high_u8(v)); // [B2,G2,R2,A2,B3,G3,R3,A3]
            let l0 = luma_quad(lo);
            let l1 = luma_quad(hi);
            let mut buf = [0u16; 8];
            vst1q_u16(buf.as_mut_ptr(), l0);
            out[i / 4] = buf[0] as u8;
            out[i / 4 + 1] = buf[2] as u8;
            vst1q_u16(buf.as_mut_ptr(), l1);
            out[i / 4 + 2] = buf[0] as u8;
            out[i / 4 + 3] = buf[2] as u8;
            i += 16;
        }
        for (idx, px) in row[i..].chunks_exact(4).enumerate() {
            let (b, g, r) = (px[0] as u32, px[1] as u32, px[2] as u32);
            out[i / 4 + idx] = ((77 * r + 150 * g + 29 * b) >> 8) as u8;
        }
    }

    /// Luma of two BGRA pixels packed as u16 lanes [B,G,R,A,B,G,R,A].
    #[inline]
    unsafe fn luma_quad(u: uint16x8_t) -> uint16x8_t {
        // Shift each 64-bit lane LEFT by 16 bits → [0,B,G,R, 0,B,G,R].
        let s = vreinterpretq_u16_u64(vshlq_n_u64(vreinterpretq_u64_u16(u), 16));
        let coef = vld1q_u16(COEF.as_ptr());
        let m = vmulq_u16(s, coef); // [0, 29B, 150G, 77R, 0, 29B', 150G', 77R']
        // Pairwise add within 64-bit lanes: [29B, 150G+77R, ...]
        let pa = vpaddq_u16(m, m); // [29B, L, 29B', L', 29B, L, 29B', L']
        // lane0 = 29B, lane1 = L → luma = lane0 + lane1. Add the lane shifted
        // right by 16 bits so lane0 becomes 29B + L and lane2 becomes 29B' + L'.
        let shifted = vreinterpretq_u16_u64(vshrq_n_u64(vreinterpretq_u64_u16(pa), 16));
        let l = vaddq_u16(pa, shifted); // lane0 = luma, lane2 = luma'
        vshrq_n_u16(l, 8)
    }

    static COEF: [u16; 8] = [0, 29, 150, 77, 0, 29, 150, 77];

    static MASK_TABLE: [[u8; 16]; 9] = [
        [0; 16],
        [0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0xFF, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0],
    ];
}

// ---------------------------------------------------------------------------
// Tests (run on the host; the scalar path is the reference)
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    /// Scalar-reference vertical box, so the SIMD vertical kernel is validated
    /// against an independent implementation (not itself).
    fn box_vertical_scalar_ref(tmp: &[u8], height: u32, out_h: u32, out_w: u32, step: u32) -> Vec<u8> {
        let h = height as usize;
        let ow = out_w as usize;
        let s = step as usize;
        let oh = out_h as usize;
        let mut out = vec![0u8; oh * ow];
        for r in 0..oh {
            let row_start = r * s;
            let n = s.min(h.saturating_sub(row_start));
            if n == 0 {
                continue;
            }
            box_columns_scalar(tmp, n, ow, &mut out[r * ow..r * ow + ow]);
        }
        out
    }

    #[test]
    fn yplane_step1_copy() {
        let w = 64u32;
        let h = 32u32;
        let raw: Vec<u8> = (0..w * h).map(|i| (i % 251) as u8).collect();
        let f = yplane_to_gray(&raw, w, h, w, 1, 1280).expect("frame");
        assert_eq!(f.width, w);
        assert_eq!(f.height, h);
        assert_eq!(f.data, raw);
    }

    #[test]
    fn yplane_strips_padding() {
        let w = 50u32;
        let h = 30u32;
        let stride = 64u32;
        let mut raw = vec![0u8; (h * stride) as usize];
        for y in 0..h {
            for x in 0..w {
                raw[(y * stride + x) as usize] = (y * 7 + x) as u8;
            }
        }
        let f = yplane_to_gray(&raw, w, h, stride, 1, 1280).expect("frame");
        assert_eq!(f.width, w);
        assert_eq!(f.height, h);
        assert_eq!(f.data.len(), (w * h) as usize);
        assert_eq!(f.data[5 * w as usize + 7], (5 * 7 + 7) as u8);
    }

    #[test]
    fn yplane_decimate_matches_scalar_reference() {
        let w = 1920u32;
        let h = 1080u32;
        let stride = 1920u32;
        let mut raw = Vec::with_capacity((w * h) as usize);
        let mut x = 0x1234_5678u32;
        for _ in 0..(w * h) {
            x = x.wrapping_mul(1664525).wrapping_add(1013904223);
            raw.push((x >> 24) as u8);
        }
        let frame = yplane_to_gray(&raw, w, h, stride, 1, 640).expect("frame");
        assert!(frame.width.max(frame.height) <= 640);

        // Scalar reference on the same input.
        let step = decimation_step(w, h, 640);
        let ow = w.div_ceil(step);
        let oh = h.div_ceil(step);
        let tmp = box_horizontal_tight(&raw, w, h, step);
        let ref_out = box_vertical_scalar_ref(&tmp, h, oh, ow, step);
        assert_eq!(frame.data, ref_out);
    }

    #[test]
    fn bgra_step1_matches_scalar() {
        let w = 320u32;
        let h = 40u32;
        let mut raw = Vec::with_capacity((w * h * 4) as usize);
        let mut x = 7u32;
        for _ in 0..(w * h) {
            x = x.wrapping_mul(1664525).wrapping_add(1013904223);
            raw.push((x >> 24) as u8); // B
            raw.push((x >> 16) as u8); // G
            raw.push((x >> 8) as u8); // R
            raw.push(0xFF); // A
        }
        let frame = bgra_to_gray(&raw, w, h, w * 4, 1280).expect("frame");
        assert_eq!(frame.width, w);
        // Compare against the scalar kernel directly.
        let mut scalar = vec![0u8; (w * h) as usize];
        for y in 0..h as usize {
            bgra_row_scalar(
                &raw[y * w as usize * 4..(y + 1) * w as usize * 4],
                &mut scalar[y * w as usize..(y + 1) * w as usize],
            );
        }
        assert_eq!(frame.data, scalar);
    }

    #[test]
    fn bgra_decimate_matches_scalar() {
        let w = 640u32;
        let h = 480u32;
        let stride = 640u32 * 4;
        let mut raw = Vec::with_capacity((w * h * 4) as usize);
        for i in 0..(w * h) {
            let v = (i * 31) as u8;
            raw.push(v); // B
            raw.push(v.wrapping_add(40)); // G
            raw.push(v.wrapping_add(80)); // R
            raw.push(0xFF);
        }
        // 640 -> 320 is an integer fit: the SIMD integer-step box path.
        let frame = bgra_to_gray(&raw, w, h, stride, 320).expect("frame");
        assert!(frame.width.max(frame.height) <= 320);
        let mut full = vec![0u8; (w * h) as usize];
        for y in 0..h as usize {
            bgra_row_scalar(
                &raw[y * stride as usize..y * stride as usize + w as usize * 4],
                &mut full[y * w as usize..(y + 1) * w as usize],
            );
        }
        let step = decimation_step(w, h, 320);
        let ow = w.div_ceil(step);
        let oh = h.div_ceil(step);
        let tmp = box_horizontal_tight(&full, w, h, step);
        let ref_out = box_vertical_scalar_ref(&tmp, h, oh, ow, step);
        assert_eq!(frame.data, ref_out);
    }

    #[test]
    fn fractional_downscale_matches_expected_dims() {
        // 1920x1080 -> 1280 must use the fractional path (not integer 960x540).
        let w = 1920u32;
        let h = 1080u32;
        let mut raw = Vec::with_capacity((w * h) as usize);
        for i in 0..(w * h) {
            raw.push((i % 251) as u8);
        }
        let frame = downscale_gray(&raw, w, h, 1280).expect("frame");
        assert_eq!(frame.width, 1280);
        assert_eq!(frame.height, 720);
        // Spot check: the fractional box must have averaged the gradient.
        // (value at any pixel is ~the source footprint mean; just check range)
        assert!(frame.data.iter().all(|&b| b < 251));
    }

    #[test]
    fn downscale_gray_roundtrip_dimensions() {
        let img = vec![128u8; 1920 * 1080];
        let f = downscale_gray(&img, 1920, 1080, 640).expect("frame");
        assert!(f.width.max(f.height) <= 640);
        assert_eq!(f.data.len() as u64, f.width as u64 * f.height as u64);
        // Uniform input stays uniform.
        assert!(f.data.iter().all(|&b| b == 128));
    }

    #[test]
    fn decimation_step_values() {
        assert_eq!(decimation_step(1280, 720, 1280), 1);
        assert_eq!(decimation_step(1920, 1080, 1280), 2);
        assert_eq!(decimation_step(3840, 2160, 1280), 3);
        assert_eq!(decimation_step(640, 480, 1280), 1);
        assert_eq!(decimation_step(10, 10, 0), 1);
    }

    #[test]
    fn yplane_len_guard() {
        assert!(yplane_len_ok(1920 * 1080, 1920, 1080, 1920, 1));
        assert!(!yplane_len_ok(10, 1920, 1080, 1920, 1));
        assert!(bgra_len_ok(1920 * 1080 * 4, 1920, 1080, 1920 * 4));
        assert!(!bgra_len_ok(100, 1920, 1080, 1920 * 4));
    }

    #[test]
    fn bgra_row_simd_matches_scalar() {
        // Fixed input covering every pixel pattern incl. high channel values.
        let w = 64usize;
        let mut row = Vec::new();
        for i in 0..w {
            let v = (i * 37) as u8;
            row.push(v); // B
            row.push(v.wrapping_add(10)); // G
            row.push(v.wrapping_add(20)); // R
            row.push(255); // A
        }
        let mut simd = vec![0u8; w];
        let mut scalar = vec![0u8; w];
        #[cfg(target_arch = "x86_64")]
        unsafe {
            sse2::bgra_row(&row, &mut simd);
        }
        #[cfg(target_arch = "aarch64")]
        unsafe {
            neon::bgra_row(&row, &mut simd);
        }
        #[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
        {
            bgra_row_scalar(&row, &mut simd);
        }
        bgra_row_scalar(&row, &mut scalar);
        assert_eq!(simd, scalar, "simd={simd:?} scalar={scalar:?}");
    }
}
