//! QR layer: encode a frame into a module matrix and decode a camera frame
//! back into raw bytes.
//!
//! Policy mirrors the reference design:
//! - **ECC level L** — in-frame ECC and the fountain code solve different
//!   problems (corruption vs erasure); at these frame sizes
//!   "decode-whole-or-discard" plus fountain redundancy wins.
//! - **Smallest version that fits** — chosen deterministically from the
//!   ISO/IEC 18004 byte-capacity table, so sender and receiver agree on what
//!   fits without handshaking.
//! - **Track, don't rescan** — after the first successful decode the receiver
//!   remembers the symbol's bounding box (a temporal ROI) and only searches
//!   that region for the next few frames. Full-frame finder-pattern searches
//!   happen on the first lock and again only after consecutive ROI misses.
//!   A large scene-brightness swing (screen switched off, hand over camera)
//!   invalidates the ROI immediately.
//! - **SIMD scan conversion** — raw camera planes are converted to tight
//!   luma and box-downscaled in Rust with arch-dispatched SIMD
//!   (SSE2 / NEON / scalar) instead of a Dart per-pixel loop (see `luma.rs`).
//!
//! Everything here is pure and allocation-bounded so it compiles unchanged
//! for `wasm32-unknown-unknown`.

use crate::api::types::{QrDecodeResult, QrMatrix, QrTrackerState};
use crate::luma;

/// Maximum payload bytes a Version-40 QR at ECC level L can carry. Frame
/// sizes above this are rejected before a session starts.
pub const MAX_QR_FRAME_BYTES: usize = 2953;

/// Default scan dimension for decoding. 640px destroys too much detail for a
/// dense QR photographed from another phone screen.
pub const DEFAULT_SCAN_DIM: u32 = 1280;

/// Fast coarse pass side; most clean camera frames solve here (~4x less
/// decoder work than the full bound).
const FAST_DIM: u32 = 640;

/// ROI expansion fraction around the last known symbol box.
const ROI_EXPAND_FRAC: f32 = 0.15;

/// Consecutive ROI misses before falling back to a full-frame search.
const ROI_FALLBACK_FAILURES: u32 = 3;

/// Consecutive misses (ROI + full-frame) before the tracker deactivates.
const TRACKER_MAX_FAILURES: u32 = 8;

/// Scene-brightness swing (mean-luma delta) that invalidates the ROI.
const SCENE_SWING: u8 = 96;

/// Smallest QR version (1..=40) whose ECC-L byte capacity holds `frame_bytes`,
/// or `None` when it does not fit in a Version-40 symbol.
pub fn qr_version_for(frame_bytes: usize) -> Option<u8> {
    if frame_bytes == 0 {
        return None;
    }
    let probe = vec![0u8; frame_bytes];
    let code = qrcodegen::QrCode::encode_binary(&probe, qrcodegen::QrCodeEcc::Low).ok()?;
    let size = code.size();
    u8::try_from((size.saturating_sub(21)) / 4 + 1).ok()
}

/// Encode raw bytes into a QR module matrix (ECC L, smallest fitting version).
///
/// Uses `qrcodegen` (≈8× faster than the previous `qrcode` crate at
/// Version-40 payloads) so the sender can sustain high frame rates even for
/// the largest frame size. Byte mode matches the ISO/IEC 18004 capacity table
/// the sender uses to pick a version.
pub fn qr_encode(data: &[u8]) -> Result<QrMatrix, String> {
    if data.is_empty() {
        return Err("qr_encode: empty payload".to_owned());
    }
    let code = qrcodegen::QrCode::encode_binary(data, qrcodegen::QrCodeEcc::Low)
        .map_err(|e| format!("qr_encode: {e}"))?;
    let size = code.size() as u32;
    let mut cells = Vec::with_capacity((size * size) as usize);
    for y in 0..size {
        for x in 0..size {
            cells.push(if code.get_module(x as i32, y as i32) {
                1
            } else {
                0
            });
        }
    }
    Ok(QrMatrix {
        width: size,
        height: size,
        cells,
    })
}

// ---------------------------------------------------------------------------
// Raw-plane tracked decode (native camera)
// ---------------------------------------------------------------------------

/// Decode a QR from a raw YUV Y plane (Android / iOS / HarmonyOS), converting
/// and box-downscaling it to scan space with SIMD, then tracking the symbol
/// across frames.
#[flutter_rust_bridge::frb(dart_async)]
pub fn qr_decode_yplane_tracked(
    y_plane: Vec<u8>,
    width: u32,
    height: u32,
    row_stride: u32,
    pixel_stride: u32,
    max_scan_dim: Option<u32>,
    tracker: QrTrackerState,
) -> Result<QrDecodeResult, String> {
    let max_dim = max_scan_dim.unwrap_or(DEFAULT_SCAN_DIM);
    let frame = luma::yplane_to_gray(&y_plane, width, height, row_stride, pixel_stride, max_dim)
        .ok_or_else(|| "qr_decode_yplane_tracked: invalid Y plane".to_owned())?;
    decode_tracked_scan(frame.data, frame.width, frame.height, max_dim, tracker)
}

/// Decode a QR from a raw BGRA8888 frame (Windows / macOS fallback), with
/// SIMD luma conversion + box downscale, then tracking.
#[flutter_rust_bridge::frb(dart_async)]
pub fn qr_decode_bgra_tracked(
    bgra: Vec<u8>,
    width: u32,
    height: u32,
    row_stride: u32,
    max_scan_dim: Option<u32>,
    tracker: QrTrackerState,
) -> Result<QrDecodeResult, String> {
    let max_dim = max_scan_dim.unwrap_or(DEFAULT_SCAN_DIM);
    let frame = luma::bgra_to_gray(&bgra, width, height, row_stride, max_dim)
        .ok_or_else(|| "qr_decode_bgra_tracked: invalid BGRA buffer".to_owned())?;
    decode_tracked_scan(frame.data, frame.width, frame.height, max_dim, tracker)
}

/// Decode a QR from a tight grayscale (luma8) buffer with ROI tracking.
///
/// Used by the web path (canvas already yields tight frames) and by callers
/// that converted to gray elsewhere.
#[flutter_rust_bridge::frb(dart_async)]
pub fn qr_decode_gray_tracked(
    gray: Vec<u8>,
    width: u32,
    height: u32,
    max_scan_dim: Option<u32>,
    tracker: QrTrackerState,
) -> Result<QrDecodeResult, String> {
    let max_dim = max_scan_dim.unwrap_or(DEFAULT_SCAN_DIM);
    let frame = luma::downscale_gray(&gray, width, height, max_dim)
        .ok_or_else(|| "qr_decode_gray_tracked: invalid grayscale buffer".to_owned())?;
    decode_tracked_scan(frame.data, frame.width, frame.height, max_dim, tracker)
}

/// Decode a QR from an RGBA buffer (web canvas path) with ROI tracking.
#[flutter_rust_bridge::frb(dart_async)]
pub fn qr_decode_rgba_tracked(
    rgba: Vec<u8>,
    width: u32,
    height: u32,
    max_scan_dim: Option<u32>,
    tracker: QrTrackerState,
) -> Result<QrDecodeResult, String> {
    let max_dim = max_scan_dim.unwrap_or(DEFAULT_SCAN_DIM);
    if width == 0 || height == 0 {
        return Err("qr_decode_rgba_tracked: empty frame".to_owned());
    }
    if (width as u64) * (height as u64) * 4 != rgba.len() as u64 {
        return Err("qr_decode_rgba_tracked: buffer size mismatch".to_owned());
    }
    let mut gray = Vec::with_capacity((width as u64 * height as u64) as usize);
    for px in rgba.chunks_exact(4) {
        let luma = (77 * px[0] as u32 + 150 * px[1] as u32 + 29 * px[2] as u32) >> 8;
        gray.push(luma as u8);
    }
    let frame = luma::downscale_gray(&gray, width, height, max_dim)
        .ok_or_else(|| "qr_decode_rgba_tracked: invalid RGBA buffer".to_owned())?;
    decode_tracked_scan(frame.data, frame.width, frame.height, max_dim, tracker)
}

// ---------------------------------------------------------------------------
// Compatibility entry points (single shot, no tracking)
// ---------------------------------------------------------------------------

/// Decode a QR from a tight grayscale (luma8) buffer (single shot).
#[flutter_rust_bridge::frb(dart_async)]
pub fn qr_decode_gray(
    gray: Vec<u8>,
    width: u32,
    height: u32,
    max_scan_dim: Option<u32>,
) -> Result<Option<Vec<u8>>, String> {
    let res = qr_decode_gray_tracked(gray, width, height, max_scan_dim, QrTrackerState::new())?;
    Ok(res.bytes)
}

/// Decode a QR from an RGBA buffer, extracting luminance first (single shot).
#[flutter_rust_bridge::frb(dart_async)]
pub fn qr_decode_rgba(
    rgba: Vec<u8>,
    width: u32,
    height: u32,
    max_scan_dim: Option<u32>,
) -> Result<Option<Vec<u8>>, String> {
    let res = qr_decode_rgba_tracked(rgba, width, height, max_scan_dim, QrTrackerState::new())?;
    Ok(res.bytes)
}

// ---------------------------------------------------------------------------
// Tracked decode core
// ---------------------------------------------------------------------------

/// A decoded QR together with its corner points in the buffer's own
/// coordinate space.
struct DecodedQr {
    bytes: Vec<u8>,
    points: Vec<(f32, f32)>,
}

/// Run one tracked decode over a *scan-space* luma buffer (larger side
/// already `<= max_dim`).
fn decode_tracked_scan(
    gray: Vec<u8>,
    width: u32,
    height: u32,
    max_dim: u32,
    tracker: QrTrackerState,
) -> Result<QrDecodeResult, String> {
    if width == 0 || height == 0 {
        return Err("decode_tracked_scan: empty frame".to_owned());
    }
    if (width as u64) * (height as u64) != gray.len() as u64 {
        return Err("decode_tracked_scan: buffer size mismatch".to_owned());
    }
    let mut t = tracker;

    // Scene-brightness tracking is only needed while following a symbol; the
    // mean-luma pass over the whole scan frame is skipped while idle (the
    // common no-signal case) to keep searching as cheap as possible.
    if t.active {
        let mean = luma::mean_luma(&gray);
        // A large scene-brightness jump (screen off, hand over the camera,
        // lamp change) makes the old geometry meaningless; restart the search.
        if t.last_threshold != 0 && mean.abs_diff(t.last_threshold) > SCENE_SWING {
            t = QrTrackerState::new();
        } else {
            t.last_threshold = mean;
        }
    }

    // ROI-first: follow the symbol we already found. The crop is small, so a
    // single TryHarder pass on the crop is both faster (no redundant 640px
    // fast-pass downscale) and more reliable for dense symbols than the
    // coarse-to-fine path.
    if t.active && t.failures < ROI_FALLBACK_FAILURES {
        if let Some((crop, ox, oy, cw, ch)) = crop_roi(&gray, width, height, &t) {
            if let Some(qr) = decode_luma(crop, cw, ch, true)? {
                let mut points = qr.points;
                for p in &mut points {
                    p.0 += ox as f32;
                    p.1 += oy as f32;
                }
                update_tracker_roi(&mut t, &points, width, height);
                return Ok(QrDecodeResult {
                    bytes: Some(qr.bytes),
                    tracker: t,
                });
            }
            t.failures += 1;
            if t.failures < ROI_FALLBACK_FAILURES {
                // Keep following; a couple of transient misses are expected.
                return Ok(QrDecodeResult {
                    bytes: None,
                    tracker: t,
                });
            }
        } else {
            t.active = false;
        }
    }

    // Full-frame finder-pattern search: first lock, or after ROI misses.
    if let Some(qr) = decode_scan_coarse_to_fine(gray, width, height, max_dim)? {
        let mut t2 = QrTrackerState::new();
        t2.last_threshold = luma::mean_luma(&gray);
        update_tracker_roi(&mut t2, &qr.points, width, height);
        t2.qr_version = qr_version_for(qr.bytes.len()).unwrap_or(0);
        return Ok(QrDecodeResult {
            bytes: Some(qr.bytes),
            tracker: t2,
        });
    }
    if t.active {
        t.failures += 1;
        if t.failures >= TRACKER_MAX_FAILURES {
            t.active = false;
        }
    }
    Ok(QrDecodeResult {
        bytes: None,
        tracker: t,
    })
}

/// Crop the region of interest around the tracked symbol, expanded by
/// [`ROI_EXPAND_FRAC`], clamped to the frame. Returns
/// `(crop, offset_x, offset_y, crop_w, crop_h)`.
fn crop_roi(
    scan: &[u8],
    sw: u32,
    sh: u32,
    t: &QrTrackerState,
) -> Option<(Vec<u8>, u32, u32, u32, u32)> {
    let w = (t.x1 - t.x0) as f32;
    let h = (t.y1 - t.y0) as f32;
    let ew = w * ROI_EXPAND_FRAC;
    let eh = h * ROI_EXPAND_FRAC;
    let x0 = (t.x0 as f32 - ew).max(0.0) as u32;
    let y0 = (t.y0 as f32 - eh).max(0.0) as u32;
    let x1 = ((t.x1 as f32 + ew).ceil() as u32).min(sw);
    let y1 = ((t.y1 as f32 + eh).ceil() as u32).min(sh);
    if x1 <= x0 || y1 <= y0 || x1 > sw || y1 > sh {
        return None;
    }
    let cw = x1 - x0;
    let ch = y1 - y0;
    if (ch as u64) * (sw as u64) > scan.len() as u64 {
        return None;
    }
    let mut crop = Vec::with_capacity((cw as u64 * ch as u64) as usize);
    for y in y0..y1 {
        let row = y as usize * sw as usize;
        crop.extend_from_slice(&scan[row + x0 as usize..row + x1 as usize]);
    }
    Some((crop, x0, y0, cw, ch))
}

/// Fold a successful decode's corner points back into the tracker.
fn update_tracker_roi(t: &mut QrTrackerState, points: &[(f32, f32)], sw: u32, sh: u32) {
    if points.is_empty() {
        // No geometry available; keep a conservative full-frame ROI so the
        // next frame still has a chance before falling back.
        t.x0 = 0;
        t.y0 = 0;
        t.x1 = sw;
        t.y1 = sh;
        t.active = true;
    } else {
        let mut min_x = f32::MAX;
        let mut min_y = f32::MAX;
        let mut max_x = f32::MIN;
        let mut max_y = f32::MIN;
        for &(px, py) in points {
            min_x = min_x.min(px);
            min_y = min_y.min(py);
            max_x = max_x.max(px);
            max_y = max_y.max(py);
        }
        t.x0 = min_x.floor().max(0.0) as u32;
        t.y0 = min_y.floor().max(0.0) as u32;
        t.x1 = (max_x.ceil() as u32).min(sw);
        t.y1 = (max_y.ceil() as u32).min(sh);
        t.active = t.x1 > t.x0 && t.y1 > t.y0;
    }
    t.hits += 1;
    t.failures = 0;
}

// ---------------------------------------------------------------------------
// Coarse-to-fine decode core
// ---------------------------------------------------------------------------

/// Coarse-to-fine decode over an owned scan-space luma buffer (no extra
/// downscale). Returns points in the buffer's coordinate space.
///
/// A fast 640px pass (no TryHarder) solves most clean camera frames; only
/// when it fails does the decoder escalate to the full scan bound with
/// TryHarder for hard frames (motion blur, glare, dense symbols).
fn decode_scan_coarse_to_fine(
    gray: Vec<u8>,
    width: u32,
    height: u32,
    max_dim: u32,
) -> Result<Option<DecodedQr>, String> {
    if max_dim <= FAST_DIM {
        return decode_luma(gray, width, height, true);
    }
    let (small, sw, sh) = downscale(&gray, width, height, FAST_DIM);
    if let Some(mut qr) = decode_luma(small, sw, sh, false)? {
        let sx = width as f32 / sw as f32;
        let sy = height as f32 / sh as f32;
        for p in &mut qr.points {
            p.0 *= sx;
            p.1 *= sy;
        }
        return Ok(Some(qr));
    }
    decode_luma(gray, width, height, true)
}

/// Box-sample a grayscale image so its larger side is `max_dim` pixels.
/// Returns `(data, width, height)`; a copy when already small enough.
fn downscale(data: &[u8], width: u32, height: u32, max_dim: u32) -> (Vec<u8>, u32, u32) {
    match luma::downscale_gray(data, width, height, max_dim) {
        Some(f) => (f.data, f.width, f.height),
        None => (data.to_vec(), width, height),
    }
}

/// Run the ZXing-derived decoder over an owned luma8 buffer.
///
/// [try_harder] trades speed for robustness; the streaming fast pass keeps it
/// off because most camera frames of a moving QR fail, and TryHarder makes
/// every failed attempt several times slower.
fn decode_luma(
    data: Vec<u8>,
    width: u32,
    height: u32,
    try_harder: bool,
) -> Result<Option<DecodedQr>, String> {
    use rxing::common::HybridBinarizer;
    use rxing::{
        BarcodeFormat, BinaryBitmap, DecodeHints, Luma8LuminanceSource, MultiFormatReader, Reader,
    };

    let source =
        Luma8LuminanceSource::new(data, width, height).map_err(|e| format!("qr_decode: {e}"))?;
    let mut bitmap = BinaryBitmap::new(HybridBinarizer::new(source));
    let mut reader = MultiFormatReader::default();
    let hints = DecodeHints {
        PossibleFormats: Some(std::collections::HashSet::from([BarcodeFormat::QR_CODE])),
        TryHarder: Some(try_harder),
        ..DecodeHints::default()
    };

    match reader.decode_with_hints(&mut bitmap, &hints) {
        Ok(result) => {
            let raw = result.getRawBytes();
            if raw.is_empty() {
                return Ok(None);
            }
            let points = result
                .getPoints()
                .iter()
                .map(|p| (p.x, p.y))
                .collect::<Vec<_>>();
            Ok(Some(DecodedQr {
                bytes: raw.to_vec(),
                points,
            }))
        }
        Err(_) => Ok(None),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::types::QrMatrix;

    #[test]
    fn qr_version_table_edges() {
        assert_eq!(qr_version_for(0), None);
        assert_eq!(qr_version_for(17), Some(1));
        assert_eq!(qr_version_for(2953), Some(40));
        assert_eq!(qr_version_for(2954), None);
        assert_eq!(qr_version_for(2953 + 1), None);
    }

    /// Renders a QR matrix into a grayscale scene the decoder can read.
    fn render_scene(
        matrix: &QrMatrix,
        scene_w: usize,
        scene_h: usize,
        module: usize,
        offset_x: usize,
        offset_y: usize,
    ) -> Vec<u8> {
        const QUIET_ZONE: usize = 4;
        let symbol_modules = matrix.width as usize + QUIET_ZONE * 2;
        let symbol_pixels = symbol_modules * module;
        let origin_x = offset_x + QUIET_ZONE * module;
        let origin_y = offset_y + QUIET_ZONE * module;
        let mut scene = vec![255u8; scene_w * scene_h];
        for y in 0..matrix.height as usize {
            for x in 0..matrix.width as usize {
                if matrix.cells[y * matrix.width as usize + x] == 0 {
                    continue;
                }
                for dy in 0..module {
                    let row = (origin_y + y * module + dy) * scene_w;
                    for dx in 0..module {
                        scene[row + origin_x + x * module + dx] = 0;
                    }
                }
            }
        }
        let _ = symbol_pixels;
        scene
    }

    #[test]
    fn qr_roundtrip_binary_payload() {
        // 1000 pseudo-random bytes including values > 0x7f (binary-safe path).
        let mut payload = Vec::with_capacity(1000);
        let mut x = 0x1234_5678u32;
        for _ in 0..1000 {
            x = x.wrapping_mul(1664525).wrapping_add(1013904223);
            payload.push((x >> 24) as u8);
        }
        let matrix = qr_encode(&payload).expect("encode");
        assert_eq!(
            matrix.width as usize * matrix.height as usize,
            matrix.cells.len()
        );
        assert!(qr_version_for(payload.len()).unwrap() <= 40);

        // Reconstruct a grayscale image (5 px per module) with a quiet zone.
        let scale = 5usize;
        let size = (matrix.width as usize + 8) * scale;
        let scene = render_scene(&matrix, size, size, scale, 0, 0);
        let decoded = qr_decode_gray(scene, size as u32, size as u32, None).expect("decode");
        assert_eq!(decoded.as_deref(), Some(payload.as_slice()));
    }

    #[test]
    fn dense_screen_qr_survives_camera_scene_downscale() {
        let mut payload = vec![0u8; 2331];
        for (index, value) in payload.iter_mut().enumerate() {
            *value = (index as u32)
                .wrapping_mul(73)
                .wrapping_add(19)
                .to_le_bytes()[0];
        }
        let matrix = qr_encode(&payload).expect("encode dense QR");
        assert_eq!(matrix.width, 161); // Version 36.

        const SCENE_WIDTH: usize = 1920;
        const SCENE_HEIGHT: usize = 1080;
        const MODULE: usize = 4;
        let symbol_pixels = (matrix.width as usize + 8) * MODULE;
        let origin_x = (SCENE_WIDTH - symbol_pixels) / 2;
        let origin_y = (SCENE_HEIGHT - symbol_pixels) / 2;
        let scene = render_scene(
            &matrix,
            SCENE_WIDTH,
            SCENE_HEIGHT,
            MODULE,
            origin_x,
            origin_y,
        );

        let decoded = qr_decode_gray(scene, SCENE_WIDTH as u32, SCENE_HEIGHT as u32, None)
            .expect("decode dense screen QR");
        assert_eq!(decoded.as_deref(), Some(payload.as_slice()));
    }

    #[test]
    fn qr_decode_rgba_path() {
        let payload = b"hello over light, \x00\xff binary \x01".to_vec();
        let matrix = qr_encode(&payload).unwrap();
        let scale = 6usize;
        let size = matrix.width as usize * scale;
        let mut img = vec![255u8; size * size * 4];
        for y in 0..matrix.height as usize {
            for x in 0..matrix.width as usize {
                if matrix.cells[y * matrix.width as usize + x] == 1 {
                    for dy in 0..scale {
                        for dx in 0..scale {
                            let idx = ((y * scale + dy) * size + (x * scale + dx)) * 4;
                            img[idx] = 0;
                            img[idx + 1] = 0;
                            img[idx + 2] = 0;
                        }
                    }
                }
            }
        }
        let decoded = qr_decode_rgba(img, size as u32, size as u32, None).unwrap();
        assert_eq!(decoded.as_deref(), Some(payload.as_slice()));
    }

    #[test]
    fn downscale_preserves_dimensions() {
        let img = vec![0u8; 1920 * 1080];
        let (out, w, h) = downscale(&img, 1920, 1080, 640);
        assert!(w.max(h) <= 640);
        assert_eq!(out.len() as u64, (w as u64) * (h as u64));
    }

    #[test]
    fn tracked_decode_locks_then_follows_roi() {
        // A dense symbol that moves between frames: the tracker must keep
        // decoding it via the ROI without ever falling back to full-frame.
        let mut payload = vec![0u8; 1200];
        for (index, value) in payload.iter_mut().enumerate() {
            *value = (index as u32).wrapping_mul(17).to_le_bytes()[0];
        }
        let matrix = qr_encode(&payload).expect("encode");
        const SCENE: usize = 1280;
        const MODULE: usize = 3;
        let mut tracker = QrTrackerState::new();

        // Frame 0: lock the symbol at offset (200, 100).
        let scene = render_scene(&matrix, SCENE, SCENE, MODULE, 200, 100);
        let r0 = qr_decode_gray_tracked(scene, SCENE as u32, SCENE as u32, None, tracker)
            .expect("decode frame 0");
        assert_eq!(r0.bytes.as_deref(), Some(payload.as_slice()));
        assert!(r0.tracker.active);
        assert_eq!(r0.tracker.failures, 0);
        tracker = r0.tracker;

        // Frames 1..=6: symbol drifts 8 px/frame; ROI must keep following.
        for frame in 1..=6 {
            let off = 200 + frame * 8;
            let scene = render_scene(&matrix, SCENE, SCENE, MODULE, off, 100);
            let r = qr_decode_gray_tracked(scene, SCENE as u32, SCENE as u32, None, tracker)
                .expect("decode tracked frame");
            assert_eq!(
                r.bytes.as_deref(),
                Some(payload.as_slice()),
                "frame {frame} must decode via ROI"
            );
            assert!(r.tracker.active);
            assert_eq!(r.tracker.failures, 0);
            tracker = r.tracker;
        }
        // The ROI should have moved with the symbol (x0 grows).
        assert!(tracker.x0 >= 200);
        assert!(tracker.hits >= 6);
    }

    #[test]
    fn tracked_decode_recovers_after_roi_miss() {
        let payload = b"tracker-recovery-test".to_vec();
        let matrix = qr_encode(&payload).expect("encode");
        const SCENE: usize = 900;
        const MODULE: usize = 6;

        // Lock at (100, 100).
        let scene = render_scene(&matrix, SCENE, SCENE, MODULE, 100, 100);
        let r0 = qr_decode_gray_tracked(
            scene,
            SCENE as u32,
            SCENE as u32,
            None,
            QrTrackerState::new(),
        )
        .expect("decode");
        let mut tracker = r0.tracker;
        assert!(tracker.active);

        // Two frames with no QR at all → ROI misses, then full-frame fallback
        // must find the symbol again at a new location.
        for _ in 0..2 {
            let blank = vec![255u8; SCENE * SCENE];
            let r = qr_decode_gray_tracked(blank, SCENE as u32, SCENE as u32, None, tracker)
                .expect("decode blank");
            assert!(r.bytes.is_none());
            tracker = r.tracker;
        }
        assert!(tracker.failures >= 2);

        // Symbol reappears at a new spot → full-frame fallback re-locks.
        let scene = render_scene(&matrix, SCENE, SCENE, MODULE, 600, 400);
        let r = qr_decode_gray_tracked(scene, SCENE as u32, SCENE as u32, None, tracker)
            .expect("decode relocated");
        assert_eq!(r.bytes.as_deref(), Some(payload.as_slice()));
        assert!(r.tracker.active);
        assert_eq!(r.tracker.failures, 0);
        assert!(
            r.tracker.x0 >= 500,
            "ROI must relocate, got {:?}",
            r.tracker
        );
    }

    #[test]
    fn tracked_decode_invalidates_on_scene_swing() {
        let payload = b"brightness-swing".to_vec();
        let matrix = qr_encode(&payload).expect("encode");
        const SCENE: usize = 800;
        const MODULE: usize = 6;

        let scene = render_scene(&matrix, SCENE, SCENE, MODULE, 80, 80);
        let r0 = qr_decode_gray_tracked(
            scene,
            SCENE as u32,
            SCENE as u32,
            None,
            QrTrackerState::new(),
        )
        .expect("decode");
        let tracker = r0.tracker;
        assert!(tracker.active);
        assert!(tracker.last_threshold > 0);

        // Simulate "screen off": the whole frame goes black. The old ROI must
        // be discarded instead of burning ROI misses.
        let dark = vec![0u8; SCENE * SCENE];
        let r = qr_decode_gray_tracked(dark, SCENE as u32, SCENE as u32, None, tracker)
            .expect("decode dark");
        assert!(r.bytes.is_none());
        assert!(!r.tracker.active, "scene swing must reset the tracker");
    }

    #[test]
    fn yplane_tracked_roundtrip() {
        // Y-plane path: simulate a 1280x720 Y frame with a QR in the middle.
        let mut payload = vec![0u8; 700];
        for (index, value) in payload.iter_mut().enumerate() {
            *value = (index as u32).wrapping_mul(29).to_le_bytes()[0];
        }
        let matrix = qr_encode(&payload).expect("encode");
        const W: usize = 1280;
        const H: usize = 720;
        const MODULE: usize = 3;
        let scene = render_scene(
            &matrix,
            W,
            H,
            MODULE,
            (W - (matrix.width as usize + 8) * MODULE) / 2,
            60,
        );
        // yplane_to_gray with step 1 (W == scan bound) just copies rows.
        let res = qr_decode_yplane_tracked(
            scene.clone(),
            W as u32,
            H as u32,
            W as u32,
            1,
            None,
            QrTrackerState::new(),
        )
        .expect("decode yplane");
        assert_eq!(res.bytes.as_deref(), Some(payload.as_slice()));
        assert!(res.tracker.active);
    }

    #[test]
    fn bgra_tracked_roundtrip() {
        // BGRA path: convert the rendered gray scene to BGRA and decode.
        let payload = b"bgra-path-test".to_vec();
        let matrix = qr_encode(&payload).expect("encode");
        const W: usize = 800;
        const H: usize = 600;
        const MODULE: usize = 4;
        let gray = render_scene(&matrix, W, H, MODULE, 100, 80);
        let mut bgra = Vec::with_capacity(W * H * 4);
        for y in 0..H {
            for x in 0..W {
                let g = gray[y * W + x];
                bgra.push(g); // B
                bgra.push(g); // G
                bgra.push(g); // R
                bgra.push(255); // A
            }
        }
        let res = qr_decode_bgra_tracked(
            bgra,
            W as u32,
            H as u32,
            (W * 4) as u32,
            None,
            QrTrackerState::new(),
        )
        .expect("decode bgra");
        assert_eq!(res.bytes.as_deref(), Some(payload.as_slice()));
        assert!(res.tracker.active);
    }
}
