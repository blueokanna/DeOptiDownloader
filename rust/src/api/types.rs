//! Data-transfer objects crossing the Rust ↔ Dart boundary.
//!
//! These are plain, serializable structs with no logic so the bridge stays
//! thin and the two sides can evolve independently. Every field is owned
//! (`String` / `Vec<u8>`), which makes the generated Dart bindings trivial.

/// A QR symbol as a binary module matrix.
///
/// `cells` is row-major and holds `width * height` entries, each `0` (light)
/// or `1` (dark). Flutter renders it by scaling to the target rectangle.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QrMatrix {
    pub width: u32,
    pub height: u32,
    pub cells: Vec<u8>,
}

/// One emitted fountain frame: the self-describing wire bytes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SenderFrame {
    /// Sequence number (also embedded in `bytes`).
    pub seq: u32,
    /// Complete frame bytes: 25-byte protocol header + payload block.
    pub bytes: Vec<u8>,
}

/// A fountain frame together with its QR rendering, produced in one FFI call
/// so the sender loop crosses the bridge only once per frame.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SenderFrameQr {
    pub frame: SenderFrame,
    pub qr: QrMatrix,
}

/// Static facts about a live sending session (all constant across a stream).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SenderInfo {
    pub session_id: u16,
    /// Source block count.
    pub k: u16,
    /// Payload bytes per frame (frame size minus the 25-byte header).
    pub block_len: u16,
    /// Protected container length in bytes.
    pub total_len: u32,
    /// Transmission mode: `"causal"`, `"systematic"` or `"rsd"`.
    pub mode: String,
    /// Total bytes per frame on the wire (header + block).
    pub frame_bytes: u32,
    /// QR version (1..=40) used to carry one frame.
    pub qr_version: u8,
}

/// Result of pushing one decoded frame into a receiving session.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PushStatus {
    /// Frame passed integrity checks and was folded into the decoder.
    Accepted,
    /// Frame was damaged, duplicated, or the transfer already completed.
    Ignored,
    /// The whole payload was recovered.
    Complete,
}

/// Outcome of one `receiver_push` call, carrying live session state so the UI
/// can render progress without a second round trip.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceiverOutcome {
    pub status: PushStatus,
    /// Recovered DCF3 container when `status == Complete`.
    pub container: Option<Vec<u8>>,
    /// Distinct frames accepted so far (drives the progress bar).
    pub collected: u32,
    pub k: Option<u16>,
    pub block_len: Option<u16>,
    pub total_len: Option<u32>,
    pub session_id: Option<u16>,
    pub mode: Option<String>,
    pub delivered: bool,
}

/// A DCF3 container as produced by the sender-side packing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackedFileData {
    pub container: Vec<u8>,
    pub original_size: u32,
    pub transmitted_size: u32,
    /// `"gzip"` or `"none"`.
    pub compression: String,
    pub encrypted: bool,
}

/// The user-visible file recovered from a DCF3 container.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OpticalFileData {
    pub name: String,
    pub mime_type: String,
    pub bytes: Vec<u8>,
    /// BLAKE3 digest of the original bytes (32 bytes).
    pub digest: Vec<u8>,
    pub compression: String,
    pub encrypted: bool,
    pub transmitted_size: u32,
}

/// A decoded session manifest: the sender's metadata shown as the first QR
/// so the receiver can preview the transfer before any data frame arrives.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ManifestInfo {
    pub session_id: u16,
    /// Source block count.
    pub k: u16,
    /// Payload bytes per fountain frame.
    pub block_len: u16,
    /// Protected container length in bytes.
    pub total_len: u32,
    /// Total bytes per frame on the wire.
    pub frame_bytes: u32,
    /// QR version (1..=40) used to carry one data frame.
    pub qr_version: u8,
    /// Transmission mode: `"causal"`, `"systematic"` or `"rsd"`.
    pub mode: String,
    pub file_name: String,
    pub mime_type: String,
    pub encrypted: bool,
}
