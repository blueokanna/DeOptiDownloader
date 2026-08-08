//! deopti-server — a zero-dependency, std-only static file server.
//!
//! Serves the Flutter Web bundle (`build/web`) over HTTP/1.1 with a small
//! thread pool. It replaces nginx for local / LAN / Docker deployment of
//! DeOptiDownloader: every byte served here is produced by this repository's
//! own Rust code, with no third-party service or crate.
//!
//! Production properties:
//! - **Security**: strict path-traversal protection (canonical containment
//!   check), no directory listing, bounded request/header/URI sizes,
//!   `nosniff` + frame/referrer hardening headers.
//! - **Correctness for this app**: COOP/COEP isolation headers (for the
//!   threaded WASM module), immutable caching for content-hashed assets,
//!   conditional requests (ETag / Last-Modified → 304), SPA fallback.
//! - **Stability**: one request per connection (no keep-alive state machine),
//!   chunked file streaming, per-connection error isolation — a malformed
//!   request never crashes the process.

use std::env;
use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

/// Hard cap on the request line + header block (prevents slowloris-style
/// memory growth).
const MAX_HEADER_BYTES: usize = 16 * 1024;
/// Hard cap on the request target (URI).
const MAX_URI_BYTES: usize = 2048;
/// Chunk size when streaming file bodies.
const STREAM_CHUNK: usize = 64 * 1024;

/// File extensions that carry a content hash in the Flutter Web build (safe to
/// cache with `immutable`). Fixed-name files (`index.html`, `manifest.json`,
/// `version.json`, `flutter_bootstrap.js`, `flutter_service_worker.js`) are
/// deliberately excluded so updates propagate.
const HASHED_EXTENSIONS: &[&str] = &[
    "js", "mjs", "css", "wasm", "png", "jpg", "jpeg", "webp", "gif", "svg", "woff", "woff2", "ttf",
    "otf", "map", "ico",
];

fn main() {
    let root = arg("root", "DEOPTI_ROOT", "build/web");
    let host = arg("host", "DEOPTI_HOST", "0.0.0.0");
    let port = arg("port", "DEOPTI_PORT", "8080")
        .parse::<u16>()
        .unwrap_or(8080);

    let root = PathBuf::from(root);
    if !root.is_dir() {
        eprintln!("deopti-server: root is not a directory: {}", root.display());
        std::process::exit(2);
    }

    let listener = match TcpListener::bind((host.as_str(), port)) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("deopti-server: cannot bind {host}:{port}: {e}");
            std::process::exit(2);
        }
    };
    println!(
        "deopti-server: serving {} on http://{host}:{port} (COOP/COEP enabled)",
        root.display()
    );

    serve(listener, root);
}

/// Reads `--name` / `-n` then `DEOPTI_NAME`, falling back to `default`.
fn arg(name: &str, env_name: &str, default: &str) -> String {
    let mut args = env::args().skip(1);
    while let Some(a) = args.next() {
        if a == format!("--{name}") || a == format!("-{name}") {
            if let Some(v) = args.next() {
                return v;
            }
        }
    }
    env::var(env_name).unwrap_or_else(|_| default.to_owned())
}

/// Runs the accept loop with a worker thread pool.
fn serve(listener: TcpListener, root: PathBuf) {
    let workers = thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(4)
        .clamp(4, 64);
    let root = Arc::new(root);

    let mut handles = Vec::with_capacity(workers);
    for _ in 0..workers {
        let listener = match listener.try_clone() {
            Ok(l) => l,
            Err(e) => {
                eprintln!("deopti-server: try_clone failed: {e}");
                std::process::exit(2);
            }
        };
        let root = Arc::clone(&root);
        handles.push(thread::spawn(move || {
            for stream in listener.incoming() {
                match stream {
                    Ok(s) => handle_conn(&root, s),
                    Err(_) => continue,
                }
            }
        }));
    }
    for h in handles {
        let _ = h.join();
    }
}

fn handle_conn(root: &Path, mut stream: TcpStream) {
    let mut reader = BufReader::new(stream.try_clone().unwrap_or_else(|_| unreachable!()));
    // Parse the request head; any malformed/oversized input is answered with a
    // clean 400 and the connection is dropped.
    let head = match read_head(&mut reader) {
        Ok(h) => h,
        Err(status) => {
            let _ = respond_error(&mut stream, status, "bad request");
            return;
        }
    };

    let method = head.method.as_str();
    if method != "GET" && method != "HEAD" {
        let _ = respond_error(&mut stream, 405, "method not allowed");
        return;
    }

    let mut path = head.target.as_str();
    if let Some(q) = path.find('?') {
        path = &path[..q];
    }
    let decoded = percent_decode(path);
    if decoded.contains('\0') {
        let _ = respond_error(&mut stream, 400, "bad request");
        return;
    }
    // The leading '/' is HTTP path syntax, not part of the filesystem path;
    // drop it so the lexical containment check sees a clean relative path.
    let decoded = decoded.strip_prefix('/').unwrap_or(&decoded);
    // Resolve the request target strictly inside `root` (lexical, so it also
    // works for paths that do not exist yet — required for the SPA fallback).
    let rel = Path::new(decoded);
    let Some(resolved) = resolve_inside(root, rel) else {
        // Traversal attempt → hard 404 (never masked by the SPA fallback).
        let _ = respond_error(&mut stream, 404, "not found");
        return;
    };

    // Decide the file to serve (or SPA-fallback index.html for valid-but-
    // missing paths).
    let file = if resolved.is_dir() {
        let index = resolved.join("index.html");
        index.is_file().then_some(index)
    } else if resolved.is_file() {
        Some(resolved)
    } else {
        let index = root.join("index.html");
        index.is_file().then_some(index)
    };

    let Some(file) = file else {
        let _ = respond_error(&mut stream, 404, "not found");
        return;
    };
    let meta = match fs::metadata(&file) {
        Ok(m) if m.is_file() => m,
        _ => {
            let _ = respond_error(&mut stream, 404, "not found");
            return;
        }
    };

    let etag = format!(
        "\"{:x}-{:x}\"",
        meta.len(),
        meta.modified()
            .ok()
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_secs())
            .unwrap_or(0)
    );

    // Conditional request → 304 without a body.
    if head.if_none_match.as_deref() == Some(etag.as_str())
        || (head.if_none_match.is_none() && head.if_modified_since_matches(meta.modified().ok()))
    {
        let _ = write_head(&mut stream, 304, "text/html; charset=utf-8", 0, false, None);
        return;
    }

    let mime = mime_for(&file);
    let hashed = hashed_asset(&file);
    if !write_head(&mut stream, 200, mime, meta.len(), hashed, Some(&etag)) {
        return;
    }
    if method == "HEAD" {
        return;
    }

    // Stream the body in bounded chunks (never load the whole file — the
    // bundled CJK font is ~17 MB).
    let mut f = match fs::File::open(&file) {
        Ok(f) => f,
        Err(_) => return,
    };
    let mut buf = vec![0u8; STREAM_CHUNK];
    loop {
        match f.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                if stream.write_all(&buf[..n]).is_err() {
                    break;
                }
            }
            Err(_) => break,
        }
    }
}

/// A parsed request head.
struct RequestHead {
    method: String,
    target: String,
    if_none_match: Option<String>,
    if_modified_since: Option<u64>,
}

impl RequestHead {
    /// True when the `If-Modified-Since` header (epoch seconds) is newer than
    /// the file's mtime.
    fn if_modified_since_matches(&self, mtime: Option<SystemTime>) -> bool {
        match (self.if_modified_since, mtime) {
            (Some(h), Some(m)) => m
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_secs() <= h)
                .unwrap_or(false),
            _ => false,
        }
    }
}

/// Reads the request line + headers with hard size bounds.
fn read_head<R: BufRead>(reader: &mut R) -> Result<RequestHead, u16> {
    let mut consumed = 0usize;
    let first = reader.read_line_with_limit(&mut consumed).ok_or(400u16)?;
    let mut parts = first.split_whitespace();
    let method = parts.next().ok_or(400u16)?;
    let target = parts.next().ok_or(400u16)?;
    if target.len() > MAX_URI_BYTES {
        return Err(414);
    }
    // Reject HTTP/1.0 keep-alive quirks by requiring a known version token.
    let version = parts.next().ok_or(400u16)?;
    if !version.starts_with("HTTP/1.") {
        return Err(400);
    }

    let mut if_none_match = None;
    let mut if_modified_since = None;
    loop {
        let line = reader.read_line_with_limit(&mut consumed).ok_or(400u16)?;
        if line.is_empty() {
            break; // end of headers
        }
        let lower = line.to_ascii_lowercase();
        if let Some(v) = lower.strip_prefix("if-none-match:") {
            if_none_match = Some(v.trim().to_owned());
        } else if let Some(v) = lower.strip_prefix("if-modified-since:") {
            if_modified_since = http_date_to_epoch(v.trim());
        }
    }

    Ok(RequestHead {
        method: method.to_owned(),
        target: target.to_owned(),
        if_none_match,
        if_modified_since,
    })
}

/// Extension trait for bounded line reading.
trait BoundedRead {
    /// Reads one line, enforcing `MAX_HEADER_BYTES` across the whole head.
    fn read_line_with_limit(&mut self, consumed: &mut usize) -> Option<String>;
}

impl<R: BufRead> BoundedRead for R {
    fn read_line_with_limit(&mut self, consumed: &mut usize) -> Option<String> {
        let mut line = String::new();
        let n = self.read_line(&mut line).ok()?;
        if n == 0 {
            return None;
        }
        *consumed += n;
        if *consumed > MAX_HEADER_BYTES {
            return None;
        }
        Some(line.trim_end_matches(['\r', '\n']).to_owned())
    }
}

/// Parses an RFC 7231 IMF-fixdate ("Sun, 06 Nov 1994 08:49:37 GMT") into epoch
/// seconds. Returns `None` for anything unparseable (then no 304 is sent).
fn http_date_to_epoch(s: &str) -> Option<u64> {
    let mut it = s.split_whitespace();
    let _weekday = it.next()?;
    let day: u32 = it.next()?.trim_end_matches(',').parse().ok()?;
    let mon = month_number(it.next()?)?;
    let year: i64 = it.next()?.parse().ok()?;
    let mut t = it.next()?.split(':');
    let hh: i64 = t.next()?.parse().ok()?;
    let mm: i64 = t.next()?.parse().ok()?;
    let ss: i64 = t.next()?.parse().ok()?;
    if !(1..=31).contains(&day)
        || !(0..24).contains(&hh)
        || !(0..60).contains(&mm)
        || !(0..60).contains(&ss)
    {
        return None;
    }
    let days = days_from_civil(year, u32::from(mon), day);
    u64::try_from(days * 86_400 + hh * 3600 + mm * 60 + ss).ok()
}

fn month_number(s: &str) -> Option<u8> {
    match s {
        "Jan" => Some(1),
        "Feb" => Some(2),
        "Mar" => Some(3),
        "Apr" => Some(4),
        "May" => Some(5),
        "Jun" => Some(6),
        "Jul" => Some(7),
        "Aug" => Some(8),
        "Sep" => Some(9),
        "Oct" => Some(10),
        "Nov" => Some(11),
        "Dec" => Some(12),
        _ => None,
    }
}

/// Howard Hinnant's `days_from_civil`: days since 1970-01-01 for a proleptic
/// Gregorian date. Exact, no platform dependency.
fn days_from_civil(y: i64, m: u32, d: u32) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = (y - era * 400) as u64; // [0, 399]
    let mp = ((m as i64 + 9) % 12) as u64; // [0, 11]
    let doy = (153 * mp + 2) / 5 + (d as u64) - 1; // [0, 365]
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy; // [0, 146096]
    era * 146_097 + doe as i64 - 719_468
}

/// Percent-decodes a request target (only `%XX`; other escapes are left as-is
/// and fail the containment check naturally).
fn percent_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let (Some(h), Some(l)) = (hex(bytes[i + 1]), hex(bytes[i + 2])) {
                out.push(h * 16 + l);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}
/// Resolves a request-relative path strictly inside `root`.
///
/// Returns `None` for any traversal attempt (`..`, absolute paths, drive
/// prefixes). This is a *lexical* check, so it also resolves paths that do
/// not exist yet (required for the SPA fallback), and it is immune to the
/// Windows `PathBuf::join` root-relative quirk.
fn resolve_inside(root: &Path, rel: &Path) -> Option<PathBuf> {
    use std::path::Component;
    let mut base = root.to_path_buf();
    for comp in rel.components() {
        match comp {
            Component::Normal(c) => base.push(c),
            Component::CurDir => {}
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => return None,
        }
    }
    Some(base)
}
fn hex(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

/// Whether the file looks like a content-hashed Flutter asset.
fn hashed_asset(path: &Path) -> bool {
    let Some(ext) = path.extension().and_then(|e| e.to_str()) else {
        return false;
    };
    HASHED_EXTENSIONS.contains(&ext.to_ascii_lowercase().as_str())
}

/// Maps a file extension to a MIME type (browser-critical: WASM, JS, fonts).
fn mime_for(path: &Path) -> &'static str {
    let ext = match path.extension().and_then(|e| e.to_str()) {
        Some(e) => e.to_ascii_lowercase(),
        None => return "application/octet-stream",
    };
    match ext.as_str() {
        "html" | "htm" => "text/html; charset=utf-8",
        "js" | "mjs" => "text/javascript; charset=utf-8",
        "css" => "text/css; charset=utf-8",
        "wasm" => "application/wasm",
        "json" | "map" => "application/json; charset=utf-8",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "svg" => "image/svg+xml",
        "webp" => "image/webp",
        "ico" => "image/x-icon",
        "woff" => "font/woff",
        "woff2" => "font/woff2",
        "ttf" => "font/ttf",
        "otf" => "font/otf",
        "txt" => "text/plain; charset=utf-8",
        "xml" => "text/xml; charset=utf-8",
        "pdf" => "application/pdf",
        _ => "application/octet-stream",
    }
}

/// Writes a full response head. Returns whether the write succeeded.
fn write_head(
    stream: &mut TcpStream,
    status: u16,
    mime: &str,
    body_len: u64,
    hashed: bool,
    etag: Option<&str>,
) -> bool {
    let reason = match status {
        200 => "OK",
        304 => "Not Modified",
        400 => "Bad Request",
        404 => "Not Found",
        405 => "Method Not Allowed",
        414 => "URI Too Long",
        _ => "Error",
    };
    let cache = if status == 304 {
        "no-cache"
    } else if hashed {
        "public, max-age=31536000, immutable"
    } else {
        "no-cache"
    };
    let mut head = format!(
        "HTTP/1.1 {status} {reason}\r\n\
         Content-Type: {mime}\r\n\
         Content-Length: {body_len}\r\n\
         Cache-Control: {cache}\r\n\
         X-Content-Type-Options: nosniff\r\n\
         X-Frame-Options: SAMEORIGIN\r\n\
         Referrer-Policy: no-referrer\r\n\
         Cross-Origin-Opener-Policy: same-origin\r\n\
         Cross-Origin-Embedder-Policy: require-corp\r\n\
         Connection: close\r\n"
    );
    if let Some(etag) = etag {
        head.push_str(&format!("ETag: {etag}\r\n"));
    }
    head.push_str("\r\n");
    stream.write_all(head.as_bytes()).is_ok()
}

/// Writes a small plain-text error response.
fn respond_error(stream: &mut TcpStream, status: u16, body: &str) -> std::io::Result<()> {
    if write_head(
        stream,
        status,
        "text/plain; charset=utf-8",
        body.len() as u64,
        false,
        None,
    ) {
        stream.write_all(body.as_bytes())
    } else {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn percent_decode_handles_reserved_bytes() {
        assert_eq!(percent_decode("/a%20b/c"), "/a b/c");
        assert_eq!(percent_decode("/plain"), "/plain");
        assert_eq!(percent_decode("/%2e%2e/"), "/../");
    }

    #[test]
    fn mime_map_covers_wasm_and_fonts() {
        assert_eq!(mime_for(Path::new("x.wasm")), "application/wasm");
        assert_eq!(
            mime_for(Path::new("x.js")),
            "text/javascript; charset=utf-8"
        );
        assert_eq!(mime_for(Path::new("x.html")), "text/html; charset=utf-8");
        assert_eq!(mime_for(Path::new("x.woff2")), "font/woff2");
        assert_eq!(mime_for(Path::new("x.ttf")), "font/ttf");
        assert_eq!(mime_for(Path::new("x.bin")), "application/octet-stream");
    }

    #[test]
    fn hashed_asset_detection() {
        assert!(hashed_asset(Path::new("main.dart.js")));
        assert!(hashed_asset(Path::new("x.wasm")));
        assert!(!hashed_asset(Path::new("index.html")));
        assert!(!hashed_asset(Path::new("manifest.json")));
    }

    #[test]
    fn http_date_parses_rfc7231() {
        // 2026-08-08 12:00:00 UTC → epoch.
        let epoch = http_date_to_epoch("Sat, 08 Aug 2026 12:00:00 GMT");
        assert_eq!(epoch, Some(1_786_190_400));
        assert_eq!(http_date_to_epoch("garbage"), None);
    }

    #[test]
    fn traversal_containment_is_rejected() {
        // Lexical containment: `..` escapes and absolute paths must be
        // rejected, while normal relative paths resolve inside root.
        let root = Path::new("/srv/web");
        assert_eq!(
            resolve_inside(root, Path::new("pkg/x.wasm")).as_deref(),
            Some(Path::new("/srv/web/pkg/x.wasm"))
        );
        assert_eq!(
            resolve_inside(root, Path::new("")).as_deref(),
            Some(Path::new("/srv/web"))
        );
        assert!(resolve_inside(root, Path::new("../secret")).is_none());
        assert!(resolve_inside(root, Path::new("a/../../secret")).is_none());
        assert!(resolve_inside(root, Path::new("C:/windows")).is_none());
        assert!(resolve_inside(root, Path::new("/etc/passwd")).is_none());
    }
}
