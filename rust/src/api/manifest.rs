//! Session manifest: a compact, bounded metadata frame the sender shows as
//! the *first* QR of a stream.
//!
//! The manifest lets the receiver preview what is coming (file name, size,
//! block layout) before any fountain frame arrives, and lets it sanity-check
//! that the stream that locks on afterwards belongs to the same session.
//!
//! Wire format:
//!
//! ```text
//! +--------+----------------------------------------+
//! | "DOTM" | rustbinary-encoded ManifestPayload     |
//! +--------+----------------------------------------+
//!   4 bytes   bounded, variable-integer, little-endian
//! ```
//!
//! The 4-byte magic makes a manifest trivially distinguishable from a
//! fountain frame (which begins with the `D1 0F` protocol magic) at the byte
//! level, so the receiver can route a decoded QR without parsing anything.
//! The payload itself is serialized with `rustbinary`'s strict compact
//! profile: variable-width integers, little endian, rejected trailing bytes,
//! and hard limits on both total size and collection sizes — a hostile camera
//! frame can never make the decoder allocate unbounded memory.

use serde::{Deserialize, Serialize};

/// Byte magic that marks a frame as a session manifest, not a fountain frame.
pub const MANIFEST_MAGIC: [u8; 4] = *b"DOTM";

/// Current manifest schema version.
pub const MANIFEST_VERSION: u8 = 1;

/// Hard cap on one encoded manifest. A manifest is a few dozen bytes; this
/// limit is far above that but still tiny enough to keep the QR small and to
/// reject anything that is not a real manifest.
const MANIFEST_SIZE_LIMIT: u64 = 512;

/// Cap on the number of elements in any serialized collection (names/MIME).
const MANIFEST_COLLECTION_LIMIT: u64 = 32;

/// Transmission mode, mirrored from `deopti_transfer::frame` flags.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum ManifestMode {
    Systematic = 0,
    Causal = 1,
    Rsd = 2,
}

/// The serialized payload of a session manifest.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ManifestPayload {
    /// Schema version (`MANIFEST_VERSION`); receivers ignore unknown versions.
    pub version: u8,
    pub session_id: u16,
    /// Source block count.
    pub k: u16,
    /// Payload bytes per fountain frame (frame size minus the 25-byte header).
    pub block_len: u16,
    /// Protected container length in bytes.
    pub total_len: u32,
    /// Total bytes per frame on the wire (header + block).
    pub frame_bytes: u16,
    pub qr_version: u8,
    pub mode: u8,
    pub encrypted: bool,
    pub file_name: String,
    pub mime_type: String,
}

/// Encode a manifest: fixed 4-byte magic followed by the bounded rustbinary
/// payload. Returns an error (never panics) when the payload is too large.
pub fn encode_manifest(payload: &ManifestPayload) -> Result<Vec<u8>, String> {
    let body = rustbinary::options()
        .with_limit(MANIFEST_SIZE_LIMIT)
        .with_collection_limit(MANIFEST_COLLECTION_LIMIT)
        .serialize(payload)
        .map_err(|e| format!("manifest encode: {e}"))?;
    let mut out = Vec::with_capacity(MANIFEST_MAGIC.len() + body.len());
    out.extend_from_slice(&MANIFEST_MAGIC);
    out.extend_from_slice(&body);
    Ok(out)
}

/// Decode a manifest from raw bytes.
///
/// Returns `Ok(None)` when the magic does not match (i.e. the bytes are not a
/// manifest — likely a fountain frame), and `Err` for a malformed manifest so
/// callers can decide whether to treat it as an erasure.
pub fn decode_manifest(bytes: &[u8]) -> Result<Option<ManifestPayload>, String> {
    if bytes.len() < MANIFEST_MAGIC.len() || bytes[..MANIFEST_MAGIC.len()] != MANIFEST_MAGIC {
        return Ok(None);
    }
    let body = &bytes[MANIFEST_MAGIC.len()..];
    let payload: ManifestPayload = rustbinary::options()
        .with_limit(MANIFEST_SIZE_LIMIT)
        .with_collection_limit(MANIFEST_COLLECTION_LIMIT)
        .deserialize(body)
        .map_err(|e| format!("manifest decode: {e}"))?;
    Ok(Some(payload))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_payload() -> ManifestPayload {
        ManifestPayload {
            version: MANIFEST_VERSION,
            session_id: 0x0c_d1,
            k: 42,
            block_len: 1465 - 25,
            total_len: 61_530,
            frame_bytes: 1465,
            qr_version: 19,
            mode: ManifestMode::Causal as u8,
            encrypted: false,
            file_name: "report.pdf".to_owned(),
            mime_type: "application/pdf".to_owned(),
        }
    }

    #[test]
    fn manifest_roundtrip() {
        let encoded = encode_manifest(&sample_payload()).expect("encode");
        assert_eq!(&encoded[..4], &MANIFEST_MAGIC);
        let decoded = decode_manifest(&encoded)
            .expect("decode")
            .expect("is manifest");
        assert_eq!(decoded, sample_payload());
    }

    #[test]
    fn fountain_frame_is_not_a_manifest() {
        // A real fountain frame begins with the D1 0F protocol magic.
        let mut frame = vec![0xD1, 0x0F, 0x00, 0x00, 0x00];
        frame.extend_from_slice(&[0xAA; 32]);
        assert!(decode_manifest(&frame).expect("decode").is_none());
    }

    #[test]
    fn manifest_rejects_truncated_and_oversized() {
        // Magic present but truncated body → decode error (not a silent miss).
        assert!(decode_manifest(&[0x44, 0x4F, 0x54, 0x4D, 0x01]).is_err());
        // Way too long input is rejected by the size limit.
        let mut blob = MANIFEST_MAGIC.to_vec();
        blob.extend_from_slice(&[0u8; 4096]);
        assert!(decode_manifest(&blob).is_err());
    }

    #[test]
    fn manifest_size_stays_tiny() {
        let encoded = encode_manifest(&sample_payload()).expect("encode");
        assert!(encoded.len() < 128, "manifest too large: {}", encoded.len());
    }
}
