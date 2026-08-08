//! FRB-facing transfer engine: DCF3 container packing, fountain sending and
//! receiving sessions, plus an end-to-end self test.
//!
//! This module is intentionally thin — all protocol logic lives in
//! `deopti_transfer`; this layer only adapts it to the bridge, owns session
//! state, and adds the small amount of glue (random session ids, stream
//! re-lock on conflict) that makes the UI ergonomic.

use std::collections::HashSet;
use std::sync::Mutex;

use deopti_transfer::container::{pack_file, unpack_file, Compression, PackedOpticalFile};
use deopti_transfer::session::{Receiver as OtReceiver, Sender as OtSender};
use deopti_transfer::{Error as OtError, HEADER_LEN, MAX_FILE_BYTES};

use crate::api::manifest::{
    decode_manifest, encode_manifest, ManifestMode, ManifestPayload, MANIFEST_VERSION,
};
use crate::api::qr::{qr_encode, qr_version_for, MAX_QR_FRAME_BYTES};
use crate::api::types::{
    ManifestInfo, OpticalFileData, PackedFileData, PushStatus, QrMatrix, ReceiverOutcome,
    SenderFrame, SenderFrameQr, SenderInfo,
};

/// Canonical on-the-wire frame sizes (header + block), matching the reference
/// sender's dropdown. All of them fit a Version-40 QR at ECC level L.
const FRAME_SIZE_OPTIONS: [usize; 6] = [500, 1000, 1465, 1850, 2331, 2953];

/// Number of extra frames (as a fraction of K) the receiver may need on a
/// noisy channel before the fountain solves. Used for progress estimation.
const FOUNTAIN_OVERHEAD: f64 = 1.15;

/// Hard cap on the original file size (the reference project's limit).
pub const MAX_SEND_BYTES: u64 = MAX_FILE_BYTES;

// ---------------------------------------------------------------------------
// init & capability
// ---------------------------------------------------------------------------

/// Default utilities for the bridge runtime.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// Whether authenticated encryption is compiled into this build.
///
/// Encryption needs `getrandom`, which is not available on the default
/// `wasm32-unknown-unknown` web build, so it is an opt-in Cargo feature there.
pub fn encryption_supported() -> bool {
    cfg!(feature = "encryption")
}

/// The reference's 64 MiB file cap.
pub fn max_file_bytes() -> u32 {
    MAX_FILE_BYTES as u32
}

/// Canonical frame sizes offered by the sender.
pub fn frame_size_options() -> Vec<u32> {
    FRAME_SIZE_OPTIONS.iter().map(|&v| v as u32).collect()
}

/// Default frame size (Version-40 QR, maximum throughput).
pub fn default_frame_size() -> u32 {
    FRAME_SIZE_OPTIONS[FRAME_SIZE_OPTIONS.len() - 1] as u32
}

/// Source blocks a payload splits into at a given frame size.
pub fn source_block_count_for(payload_len: u32, frame_bytes: u32) -> Option<u32> {
    deopti_transfer::source_block_count(payload_len as usize, frame_bytes as usize)
        .map(|v| v as u32)
}

/// Whether a payload fits a single stream at a given frame size.
pub fn fits_in_one_stream(payload_len: u32, frame_bytes: u32) -> bool {
    deopti_transfer::fits_in_one_stream(payload_len as usize, frame_bytes as usize)
}

/// The smallest canonical frame size that can carry `payload_len` bytes.
pub fn smallest_sufficient_frame_size_for(payload_len: u32) -> Option<u32> {
    deopti_transfer::smallest_sufficient_frame_size(payload_len as usize, &FRAME_SIZE_OPTIONS)
        .map(|v| v as u32)
}

/// Fountain redundancy factor: the receiver may need ~K × this many distinct
/// frames on a noisy channel. Used for progress estimation.
pub fn fountain_overhead() -> f64 {
    FOUNTAIN_OVERHEAD
}

// ---------------------------------------------------------------------------
// DCF3 container packing
// ---------------------------------------------------------------------------

/// Pack a file (name + MIME + bytes) into a DCF3 container.
pub fn pack_file_ffi(
    name: String,
    mime_type: String,
    bytes: Vec<u8>,
) -> Result<PackedFileData, String> {
    let packed: PackedOpticalFile = pack_file(&name, &mime_type, &bytes).map_err(ot_error)?;
    Ok(to_packed_data(packed))
}

/// Pack with optional password encryption (only in `encryption` builds).
pub fn pack_file_encrypted_ffi(
    name: String,
    mime_type: String,
    bytes: Vec<u8>,
    password: String,
) -> Result<PackedFileData, String> {
    #[cfg(feature = "encryption")]
    {
        if password.is_empty() {
            return Err("password must not be empty".to_owned());
        }
        use deopti_transfer::container::pack_file_encrypted_with_password;
        use deopti_transfer::crypto::random_nonce;
        let nonce = random_nonce().map_err(|e| format!("nonce: {e}"))?;
        let packed = pack_file_encrypted_with_password(
            &name,
            &mime_type,
            &bytes,
            password.as_bytes(),
            &nonce,
        )
        .map_err(ot_error)?;
        Ok(to_packed_data(packed))
    }
    #[cfg(not(feature = "encryption"))]
    {
        let _ = (name, mime_type, bytes, password);
        Err("encryption is not enabled in this build".to_owned())
    }
}

/// Recover the original file from a plain DCF3 container.
pub fn unpack_file_ffi(container: Vec<u8>) -> Result<OpticalFileData, String> {
    let file = unpack_file(&container).map_err(ot_error)?;
    Ok(to_file_data(file))
}

/// Recover a password-encrypted DCF3 container (only in `encryption` builds).
pub fn unpack_file_with_password_ffi(
    container: Vec<u8>,
    password: String,
) -> Result<OpticalFileData, String> {
    #[cfg(feature = "encryption")]
    {
        use deopti_transfer::container::unpack_file_with_password;
        let file = unpack_file_with_password(&container, password.as_bytes()).map_err(ot_error)?;
        Ok(to_file_data(file))
    }
    #[cfg(not(feature = "encryption"))]
    {
        let _ = (container, password);
        Err("encryption is not enabled in this build".to_owned())
    }
}

// ---------------------------------------------------------------------------
// Sending session
// ---------------------------------------------------------------------------

/// Opaque handle to one sending session.
#[flutter_rust_bridge::frb(opaque)]
pub struct SenderSession {
    inner: Mutex<SenderState>,
}

struct SenderState {
    sender: OtSender,
    frame_bytes: usize,
    block_len: usize,
    total_len: usize,
    session_id: u16,
    qr_version: u8,
    /// Original file metadata carried by the manifest QR.
    encrypted: bool,
    file_name: String,
    mime_type: String,
}

/// Create a sending session for an already-packed container.
///
/// `frame_bytes` is the total on-the-wire frame size (header + block); the
/// session derives `block_len` from it. A fresh random `session_id` is picked
/// unless one is supplied (useful for deterministic tests).
pub fn sender_create(
    container: Vec<u8>,
    frame_bytes: u32,
    session_id: Option<u16>,
) -> Result<SenderSession, String> {
    if container.is_empty() {
        return Err("empty container".to_owned());
    }
    let frame_bytes = frame_bytes as usize;
    let block_len = frame_bytes
        .checked_sub(HEADER_LEN)
        .filter(|&b| b > 0 && b <= u16::MAX as usize)
        .ok_or_else(|| format!("invalid frame size {frame_bytes}"))?;
    if frame_bytes > MAX_QR_FRAME_BYTES {
        return Err(format!(
            "frame size {frame_bytes} exceeds QR capacity {MAX_QR_FRAME_BYTES}"
        ));
    }
    let qr_version = qr_version_for(frame_bytes)
        .ok_or_else(|| format!("frame size {frame_bytes} not encodable"))?;
    let sid = session_id.unwrap_or_else(random_u16);
    let total_len = container.len();
    let (encrypted, file_name, mime_type) = container_metadata(&container);
    let sender = OtSender::try_new(&container, block_len, sid).map_err(ot_error)?;
    Ok(SenderSession {
        inner: Mutex::new(SenderState {
            sender,
            frame_bytes,
            block_len,
            total_len,
            session_id: sid,
            qr_version,
            encrypted,
            file_name,
            mime_type,
        }),
    })
}

/// Pull the original file metadata out of a DCF3 container for the manifest.
///
/// The DCF3 header is a fixed-width little-endian block of
/// [`deopti_transfer::container::FILE_HEADER_LEN`] bytes (documented by the
/// crate): `magic[4] flags[1] name_len[2] type_len[2] file_len[4] xmit_len[4]
/// digest[32] nonce[24]`, followed by the name and MIME bytes. We read only
/// that prefix — never decompressing or decrypting — so the manifest is cheap
/// for every frame size. Fails softly: a malformed container yields empty
/// metadata (the manifest is a convenience, never a correctness requirement).
fn container_metadata(container: &[u8]) -> (bool, String, String) {
    use deopti_transfer::container::FILE_HEADER_LEN;
    if container.len() < FILE_HEADER_LEN {
        return (false, String::new(), String::new());
    }
    // DCF3 header layout (little-endian, fixed width).
    const FLAG_CRYPT: u8 = 2;
    let flags = container[4];
    let name_len = u16::from_le_bytes([container[5], container[6]]) as usize;
    let type_len = u16::from_le_bytes([container[7], container[8]]) as usize;
    let data_end = FILE_HEADER_LEN + name_len + type_len;
    if data_end > container.len() {
        return (false, String::new(), String::new());
    }
    let name = String::from_utf8_lossy(&container[FILE_HEADER_LEN..FILE_HEADER_LEN + name_len])
        .into_owned();
    let mime = String::from_utf8_lossy(
        &container[FILE_HEADER_LEN + name_len..FILE_HEADER_LEN + name_len + type_len],
    )
    .into_owned();
    (flags & FLAG_CRYPT != 0, name, mime)
}

/// Static facts about a sending session.
pub fn sender_info(session: &SenderSession) -> SenderInfo {
    let st = session.inner.lock().expect("sender lock poisoned");
    SenderInfo {
        session_id: st.session_id,
        k: st.sender.k(),
        block_len: st.block_len as u16,
        total_len: st.total_len as u32,
        mode: "causal".to_owned(),
        frame_bytes: st.frame_bytes as u32,
        qr_version: st.qr_version,
    }
}

/// Emit the next fountain frame (wire bytes only).
pub fn sender_next(session: &SenderSession) -> Result<SenderFrame, String> {
    let mut st = session.inner.lock().expect("sender lock poisoned");
    let frame = st.sender.try_next_frame().map_err(ot_error)?;
    Ok(SenderFrame {
        seq: frame.header.seq,
        bytes: frame.to_bytes(),
    })
}

/// Emit the next frame together with its QR matrix in one bridge call.
pub fn sender_next_qr(session: &SenderSession) -> Result<SenderFrameQr, String> {
    let frame = sender_next(session)?;
    let qr = qr_encode(&frame.bytes)?;
    Ok(SenderFrameQr { frame, qr })
}

/// Generate the QR for arbitrary bytes (used for the session helper QR).
pub fn qr_encode_frame(bytes: Vec<u8>) -> Result<QrMatrix, String> {
    qr_encode(&bytes)
}

/// Build the session-manifest QR for a live sending session.
///
/// This is the *first* QR a receiver should scan: it carries the file name,
/// size and block layout so the receiving side can preview the transfer and
/// verify that the stream which locks on afterwards belongs to this session.
pub fn session_manifest_qr(session: &SenderSession) -> Result<QrMatrix, String> {
    let st = session.inner.lock().expect("sender lock poisoned");
    let manifest = manifest_for(&st);
    let bytes = encode_manifest(&manifest)?;
    qr_encode(&bytes)
}

/// Raw encoded session manifest for a live sending session (diagnostics and
/// tests). The QR variant is what the UI shows; this returns the wire bytes.
pub fn session_manifest_bytes(session: &SenderSession) -> Result<Vec<u8>, String> {
    let st = session.inner.lock().expect("sender lock poisoned");
    let manifest = manifest_for(&st);
    encode_manifest(&manifest)
}

/// Decode raw bytes as a session manifest, if they are one.
///
/// Returns `Ok(None)` when the bytes are not a manifest (e.g. a fountain
/// frame) and `Err` for a malformed manifest, so callers can route decoded
/// QR payloads without a protocol dependency.
pub fn decode_manifest_ffi(bytes: Vec<u8>) -> Result<Option<ManifestInfo>, String> {
    match decode_manifest(&bytes)? {
        Some(p) => Ok(Some(to_manifest_info(p))),
        None => Ok(None),
    }
}

/// Build a `ManifestPayload` from the live sender state.
fn manifest_for(st: &SenderState) -> ManifestPayload {
    ManifestPayload {
        version: MANIFEST_VERSION,
        session_id: st.session_id,
        k: st.sender.k(),
        block_len: st.block_len as u16,
        total_len: st.total_len as u32,
        frame_bytes: st.frame_bytes as u16,
        qr_version: st.qr_version,
        mode: ManifestMode::Causal as u8,
        encrypted: st.encrypted,
        file_name: st.file_name.clone(),
        mime_type: st.mime_type.clone(),
    }
}

fn to_manifest_info(p: ManifestPayload) -> ManifestInfo {
    ManifestInfo {
        session_id: p.session_id,
        k: p.k,
        block_len: p.block_len,
        total_len: p.total_len,
        frame_bytes: p.frame_bytes as u32,
        qr_version: p.qr_version,
        mode: match p.mode {
            m if m == ManifestMode::Systematic as u8 => "systematic".to_owned(),
            m if m == ManifestMode::Causal as u8 => "causal".to_owned(),
            _ => "rsd".to_owned(),
        },
        file_name: p.file_name,
        mime_type: p.mime_type,
        encrypted: p.encrypted,
    }
}

// ---------------------------------------------------------------------------
// Receiving session
// ---------------------------------------------------------------------------

/// Opaque handle to one receiving session. It locks to the first stream
/// identity it sees and re-locks automatically when a *different* stream
/// (a restarted sender) appears.
#[flutter_rust_bridge::frb(opaque)]
pub struct ReceiverSession {
    inner: Mutex<ReceiverState>,
}

struct ReceiverState {
    receiver: OtReceiver,
    /// Distinct sequence numbers accepted so far (progress metric).
    seen: HashSet<u32>,
}

/// Create a fresh receiving session.
pub fn receiver_create() -> ReceiverSession {
    ReceiverSession {
        inner: Mutex::new(ReceiverState {
            receiver: OtReceiver::new(),
            seen: HashSet::new(),
        }),
    }
}

/// Push one decoded frame into the receiver.
///
/// Corrupt frames are treated as erasures (the fountain absorbs them);
/// frames from a different stream cause an automatic re-lock so a restarted
/// sender is picked up immediately.
pub fn receiver_push(
    session: &ReceiverSession,
    frame_bytes: Vec<u8>,
) -> Result<ReceiverOutcome, String> {
    let mut st = session.inner.lock().expect("receiver lock poisoned");

    // Auto re-lock: a foreign stream means a new sender session — reset.
    if let Err(OtError::StreamConflict) = st.receiver.try_push(&frame_bytes) {
        st.receiver.reset();
        st.seen.clear();
    }

    match st.receiver.try_push(&frame_bytes) {
        Ok(Some(container)) => {
            if let Some((h, _)) = deopti_transfer::frame::parse_frame(&frame_bytes) {
                st.seen.insert(h.seq);
            }
            Ok(ReceiverOutcome {
                status: PushStatus::Complete,
                container: Some(container),
                collected: st.seen.len() as u32,
                k: None,
                block_len: None,
                total_len: None,
                session_id: None,
                mode: None,
                delivered: true,
            })
        }
        Ok(None) => {
            // Track distinct frames for progress (seq comes from the header).
            if let Some((h, _)) = deopti_transfer::frame::parse_frame(&frame_bytes) {
                st.seen.insert(h.seq);
            }
            let info = receiver_identity(&st.receiver);
            Ok(ReceiverOutcome {
                status: PushStatus::Accepted,
                container: None,
                collected: st.seen.len() as u32,
                k: info.k,
                block_len: info.block_len,
                total_len: info.total_len,
                session_id: info.session_id,
                mode: info.mode,
                delivered: false,
            })
        }
        Err(_) => {
            // Damaged frame → erasure. The fountain absorbs it; no error.
            let info = receiver_identity(&st.receiver);
            Ok(ReceiverOutcome {
                status: PushStatus::Ignored,
                container: None,
                collected: st.seen.len() as u32,
                k: info.k,
                block_len: info.block_len,
                total_len: info.total_len,
                session_id: info.session_id,
                mode: info.mode,
                delivered: false,
            })
        }
    }
}

/// Live state of the receiver (identity + progress), for UI refreshes.
pub fn receiver_state(session: &ReceiverSession) -> ReceiverOutcome {
    let st = session.inner.lock().expect("receiver lock poisoned");
    let info = receiver_identity(&st.receiver);
    ReceiverOutcome {
        status: if st.receiver.is_active() {
            PushStatus::Accepted
        } else {
            PushStatus::Ignored
        },
        container: None,
        collected: st.seen.len() as u32,
        k: info.k,
        block_len: info.block_len,
        total_len: info.total_len,
        session_id: info.session_id,
        mode: info.mode,
        delivered: false,
    }
}

// Small projection used internally; mirrors deopti_transfer's identity.
struct ReceiverIdentity {
    k: Option<u16>,
    block_len: Option<u16>,
    total_len: Option<u32>,
    session_id: Option<u16>,
    mode: Option<String>,
}

fn receiver_identity(receiver: &OtReceiver) -> ReceiverIdentity {
    use deopti_transfer::frame::{FLAG_CAUSAL, FLAG_SYSTEMATIC};
    match receiver.identity() {
        Some(id) => ReceiverIdentity {
            k: Some(id.k),
            block_len: Some(id.block_len),
            total_len: Some(id.total_len),
            session_id: Some(id.session_id),
            mode: Some(match id.flags {
                FLAG_SYSTEMATIC => "systematic".to_owned(),
                FLAG_CAUSAL => "causal".to_owned(),
                _ => "rsd".to_owned(),
            }),
        },
        None => ReceiverIdentity {
            k: None,
            block_len: None,
            total_len: None,
            session_id: None,
            mode: None,
        },
    }
}

/// Run a full pack → send → receive → unpack round trip in-process.
/// Returns `true` on success; used by the app's diagnostics and by tests.
pub fn run_self_test() -> Result<bool, String> {
    let name = "self-test.bin".to_owned();
    let mime = "application/octet-stream".to_owned();
    let payload: Vec<u8> = (0..4096u32).map(|i| (i % 251) as u8).collect();

    let packed = pack_file(&name, &mime, &payload).map_err(ot_error)?;
    let container = packed.container.clone();

    let frame_bytes =
        deopti_transfer::smallest_sufficient_frame_size(container.len(), &FRAME_SIZE_OPTIONS)
            .ok_or_else(|| "no frame size fits payload".to_owned())?;
    let sender =
        OtSender::try_new(&container, frame_bytes - HEADER_LEN, 0x0c_d1).map_err(ot_error)?;
    let mut sender = sender;
    let mut receiver = OtReceiver::new();
    let mut recovered = None;

    // Transmit up to ~8x K frames; the causal weave solves in exactly K.
    for _ in 0..(sender.k() as usize) * 8 {
        let frame = sender.try_next_frame().map_err(ot_error)?;
        if let Some(container) = receiver.try_push(&frame.to_bytes()).map_err(ot_error)? {
            recovered = Some(container);
            break;
        }
    }
    let container = recovered.ok_or_else(|| "stream did not complete".to_owned())?;
    let file = unpack_file(&container).map_err(ot_error)?;
    if file.bytes != payload {
        return Err("payload mismatch".to_owned());
    }
    Ok(true)
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

fn to_packed_data(p: PackedOpticalFile) -> PackedFileData {
    PackedFileData {
        container: p.container,
        original_size: p.original_size as u32,
        transmitted_size: p.transmitted_size as u32,
        compression: match p.compression {
            Compression::Gzip => "gzip".to_owned(),
            Compression::None => "none".to_owned(),
        },
        encrypted: p.encrypted,
    }
}

fn to_file_data(f: deopti_transfer::container::OpticalFile) -> OpticalFileData {
    OpticalFileData {
        name: f.name,
        mime_type: f.mime_type,
        bytes: f.bytes,
        digest: f.digest.to_vec(),
        compression: match f.compression {
            Compression::Gzip => "gzip".to_owned(),
            Compression::None => "none".to_owned(),
        },
        encrypted: f.encrypted,
        transmitted_size: f.transmitted_size as u32,
    }
}

fn ot_error(e: OtError) -> String {
    match e {
        OtError::TooLarge { len, max } => format!("{len} bytes exceeds the {max}-byte limit"),
        OtError::NoEncryption => {
            "this container is encrypted; enable the encryption build".to_owned()
        }
        other => other.to_string(),
    }
}

/// Non-cryptographic random `u16` for the session id.
///
/// Deliberately avoids every platform-dependent API: `SystemTime` and
/// `std::process::id` both panic on `wasm32-unknown-unknown` (the Web build).
/// Instead we mix a process-global atomic counter with stack-address entropy
/// — plenty for a session id, which is not a secret: it only distinguishes
/// concurrent streams on the receiver.
fn random_u16() -> u16 {
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0x9E37_79B9_7F4A_7C15);
    let counter = COUNTER.fetch_add(1, Ordering::Relaxed);
    let addr = std::ptr::addr_of!(counter) as u64;
    let mut x = counter ^ addr.rotate_left(23).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    x = (x ^ (x >> 30)).wrapping_mul(0x94D0_49BB_1331_11EB);
    x = (x ^ (x >> 27)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    (x ^ (x >> 31)) as u16
}
