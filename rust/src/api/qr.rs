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
//! - **Downscale before decode** — camera frames are far larger than the QR
//!   needs; a box-sampled downscale to ~640px keeps module size ~3px and
//!   makes binarization fast and stable.
//!
//! Everything here is pure and allocation-bounded so it compiles unchanged
//! for `wasm32-unknown-unknown`.

use crate::api::types::QrMatrix;

/// Maximum payload bytes a Version-40 QR at ECC level L can carry. Frame
/// sizes above this are rejected before a session starts.
pub const MAX_QR_FRAME_BYTES: usize = 2953;

/// Default scan dimension for decoding: frames are downscaled so the larger
/// side is at most this many pixels.
pub const DEFAULT_SCAN_DIM: u32 = 640;

/// Byte-mode capacity at ECC level L for QR versions 1..=40 (ISO/IEC 18004).
const QR_L_BYTE_CAPACITY: [u16; 40] = [
    17, 32, 53, 78, 106, 134, 154, 192, 230, 271, 321, 367, 425, 458, 520, 586, 644, 718, 792, 858,
    929, 1003, 1091, 1171, 1273, 1353, 1431, 1511, 1593, 1679, 1755, 1843, 1927, 2011, 2103, 2189,
    2275, 2369, 2455, 2953,
];

/// Smallest QR version (1..=40) whose ECC-L byte capacity holds `frame_bytes`,
/// or `None` when it does not fit in a Version-40 symbol.
pub fn qr_version_for(frame_bytes: usize) -> Option<u8> {
    if frame_bytes == 0 || frame_bytes > MAX_QR_FRAME_BYTES {
        return None;
    }
    QR_L_BYTE_CAPACITY
        .iter()
        .position(|&cap| (cap as usize) >= frame_bytes)
        .map(|i| (i + 1) as u8)
}

/// Encode raw bytes into a QR module matrix (ECC L, smallest fitting version).
pub fn qr_encode(data: &[u8]) -> Result<QrMatrix, String> {
    if data.is_empty() {
        return Err("qr_encode: empty payload".to_owned());
    }
    let code = qrcode::QrCode::with_error_correction_level(data, qrcode::EcLevel::L)
        .map_err(|e| format!("qr_encode: {e}"))?;
    let width = code.width() as u32;
    let cells: Vec<u8> = code
        .into_colors()
        .into_iter()
        .map(|c| match c {
            qrcode::Color::Dark => 1,
            qrcode::Color::Light => 0,
        })
        .collect();
    Ok(QrMatrix {
        width,
        height: width,
        cells,
    })
}

/// Decode a QR from a tight grayscale (luma8) buffer, optionally downscaled.
pub fn qr_decode_gray(
    gray: Vec<u8>,
    width: u32,
    height: u32,
    max_scan_dim: Option<u32>,
) -> Result<Option<Vec<u8>>, String> {
    if width == 0 || height == 0 {
        return Err("qr_decode_gray: empty frame".to_owned());
    }
    if (width as u64) * (height as u64) != gray.len() as u64 {
        return Err("qr_decode_gray: buffer size mismatch".to_owned());
    }
    let (data, w, h) = downscale(
        &gray,
        width,
        height,
        max_scan_dim.unwrap_or(DEFAULT_SCAN_DIM),
    );
    decode_luma(&data, w, h)
}

/// Decode a QR from an RGBA buffer, extracting luminance first.
pub fn qr_decode_rgba(
    rgba: Vec<u8>,
    width: u32,
    height: u32,
    max_scan_dim: Option<u32>,
) -> Result<Option<Vec<u8>>, String> {
    if width == 0 || height == 0 {
        return Err("qr_decode_rgba: empty frame".to_owned());
    }
    if (width as u64) * (height as u64) * 4 != rgba.len() as u64 {
        return Err("qr_decode_rgba: buffer size mismatch".to_owned());
    }
    // Luma from sRGB: 0.299 R + 0.587 G + 0.114 B (integer approximation).
    let mut gray = Vec::with_capacity((width * height) as usize);
    for px in rgba.chunks_exact(4) {
        let luma = (77 * px[0] as u32 + 150 * px[1] as u32 + 29 * px[2] as u32) >> 8;
        gray.push(luma as u8);
    }
    let (data, w, h) = downscale(
        &gray,
        width,
        height,
        max_scan_dim.unwrap_or(DEFAULT_SCAN_DIM),
    );
    decode_luma(&data, w, h)
}

/// Box-sample a grayscale image so its larger side is `max_dim` pixels.
/// Returns `(data, width, height)`; unchanged when already small enough.
fn downscale(data: &[u8], width: u32, height: u32, max_dim: u32) -> (Vec<u8>, u32, u32) {
    let max_side = width.max(height);
    if max_side <= max_dim || max_dim == 0 {
        return (data.to_vec(), width, height);
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
    (out, nw, nh)
}

/// Run the ZXing-derived decoder over a luma8 buffer.
fn decode_luma(data: &[u8], width: u32, height: u32) -> Result<Option<Vec<u8>>, String> {
    use rxing::common::HybridBinarizer;
    use rxing::{
        BarcodeFormat, BinaryBitmap, DecodeHints, Luma8LuminanceSource, MultiFormatReader, Reader,
    };

    let source = Luma8LuminanceSource::new(data.to_vec(), width, height)
        .map_err(|e| format!("qr_decode: {e}"))?;
    let mut bitmap = BinaryBitmap::new(HybridBinarizer::new(source));
    let mut reader = MultiFormatReader::default();
    let hints = DecodeHints {
        PossibleFormats: Some(std::collections::HashSet::from([BarcodeFormat::QR_CODE])),
        TryHarder: Some(true),
        ..DecodeHints::default()
    };

    match reader.decode_with_hints(&mut bitmap, &hints) {
        Ok(result) => {
            let raw = result.getRawBytes();
            if raw.is_empty() {
                Ok(None)
            } else {
                Ok(Some(raw.to_vec()))
            }
        }
        Err(_) => Ok(None),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn qr_version_table_edges() {
        assert_eq!(qr_version_for(0), None);
        assert_eq!(qr_version_for(17), Some(1));
        assert_eq!(qr_version_for(2953), Some(40));
        assert_eq!(qr_version_for(2954), None);
        assert_eq!(qr_version_for(2953 + 1), None);
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

        // Reconstruct a grayscale image (5 px per module, light bg, dark modules).
        let scale = 5usize;
        let size = matrix.width as usize * scale;
        let mut img = vec![255u8; size * size];
        for y in 0..matrix.height as usize {
            for x in 0..matrix.width as usize {
                if matrix.cells[y * matrix.width as usize + x] == 1 {
                    for dy in 0..scale {
                        for dx in 0..scale {
                            img[(y * scale + dy) * size + (x * scale + dx)] = 0;
                        }
                    }
                }
            }
        }
        let decoded = qr_decode_gray(img, size as u32, size as u32, None).expect("decode");
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
}
