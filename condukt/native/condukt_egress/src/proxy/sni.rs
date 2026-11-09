//! Minimal SNI extraction from a TLS ClientHello.
//!
//! We don't need a full TLS parser here, just the hostname in the
//! `server_name` extension. The `tls-parser` crate handles ClientHello
//! framing and extension parsing without pulling in a TLS stack.

use tls_parser::{
    TlsExtension, TlsMessage, TlsMessageHandshake, parse_tls_extensions, parse_tls_plaintext,
};

/// Attempt to extract the SNI hostname from the bytes already peeked
/// from a TCP stream. Returns `None` if the bytes do not look like a
/// TLS ClientHello, or if no SNI extension is present.
pub fn extract(bytes: &[u8]) -> Option<String> {
    let (_, plaintext) = parse_tls_plaintext(bytes).ok()?;

    for message in plaintext.msg {
        if let TlsMessage::Handshake(TlsMessageHandshake::ClientHello(ch)) = message {
            let extensions = ch.ext?;
            let (_, parsed) = parse_tls_extensions(extensions).ok()?;
            for ext in parsed {
                if let TlsExtension::SNI(entries) = ext {
                    for (_kind, name) in entries {
                        if let Ok(host) = std::str::from_utf8(name) {
                            return Some(host.to_string());
                        }
                    }
                }
            }
        }
    }

    None
}

/// True if the first few bytes look like a TLS handshake (`0x16` content
/// type, plus a plausible protocol version). Used to distinguish TLS
/// traffic from cleartext HTTP without a full parse.
pub fn looks_like_tls(bytes: &[u8]) -> bool {
    bytes.len() >= 3 && bytes[0] == 0x16 && bytes[1] == 0x03
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn looks_like_tls_recognises_handshake() {
        assert!(looks_like_tls(&[0x16, 0x03, 0x01]));
        assert!(looks_like_tls(&[0x16, 0x03, 0x03]));
        assert!(!looks_like_tls(b"GET / HTTP/1.1\r\n"));
        assert!(!looks_like_tls(&[]));
    }

    #[test]
    fn extract_returns_none_for_non_tls() {
        assert!(extract(b"GET / HTTP/1.1\r\nHost: example.com\r\n\r\n").is_none());
        assert!(extract(&[]).is_none());
        assert!(extract(&[0x00, 0x00, 0x00]).is_none());
    }

    /// End-to-end SNI extraction is exercised against a real ClientHello
    /// in the proxy integration tests (P5+ landing in CI). Here we only
    /// verify the API contract: non-TLS input returns `None` rather than
    /// erroring, and the TLS sniff helper recognises the handshake byte
    /// pattern. The `tls-parser` crate has its own coverage for the
    /// ClientHello parser itself.
    #[test]
    fn truncated_tls_handshake_returns_none() {
        // Looks like TLS by content type but isn't a valid record.
        assert!(extract(&[0x16, 0x03, 0x01, 0x00, 0x05]).is_none());
    }
}
