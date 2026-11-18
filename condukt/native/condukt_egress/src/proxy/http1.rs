//! Minimal HTTP/1.1 request-line + headers capture for the
//! TLS-terminating MITM path.
//!
//! We only inspect the request line and headers; the body is forwarded
//! through opaquely. This is enough to surface method, path, and
//! headers in `Net.Request` events without buying into a full HTTP
//! stack (hyper, etc.) just to peek at metadata.

use httparse::Status;
use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct RequestHead {
    pub method: String,
    pub path: String,
    pub headers: HashMap<String, String>,
}

/// Try to parse the head of an HTTP/1.1 request from `buf`. Returns
/// `Ok(Some(head))` if a complete request head was parsed,
/// `Ok(None)` if more bytes are needed, or `Err` on malformed input.
pub fn parse(buf: &[u8]) -> Result<Option<RequestHead>, httparse::Error> {
    let mut headers = [httparse::EMPTY_HEADER; 64];
    let mut req = httparse::Request::new(&mut headers);

    match req.parse(buf)? {
        Status::Complete(_) => {}
        Status::Partial => return Ok(None),
    }

    let method = req.method.unwrap_or("").to_string();
    let path = req.path.unwrap_or("/").to_string();

    let mut hmap = HashMap::with_capacity(req.headers.len());
    for h in req.headers.iter() {
        if !h.name.is_empty() {
            let v = std::str::from_utf8(h.value).unwrap_or("").to_string();
            hmap.insert(h.name.to_ascii_lowercase(), v);
        }
    }

    Ok(Some(RequestHead {
        method,
        path,
        headers: hmap,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_get_request() {
        let buf =
            b"GET /repos HTTP/1.1\r\nHost: api.github.com\r\nAuthorization: Bearer xyz\r\n\r\n";
        let head = parse(buf).unwrap().unwrap();
        assert_eq!(head.method, "GET");
        assert_eq!(head.path, "/repos");
        assert_eq!(
            head.headers.get("host").map(|s| s.as_str()),
            Some("api.github.com")
        );
        assert_eq!(
            head.headers.get("authorization").map(|s| s.as_str()),
            Some("Bearer xyz")
        );
    }

    #[test]
    fn partial_returns_none() {
        let buf = b"GET /repos HTTP/1.1\r\nHost: api.github.com\r\n";
        assert!(parse(buf).unwrap().is_none());
    }
}
