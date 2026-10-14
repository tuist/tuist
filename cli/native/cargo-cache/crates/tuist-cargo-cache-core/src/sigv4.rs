//! AWS Signature Version 4 request signing.
//!
//! Only what an S3 object store needs: `GET`, `HEAD`, and `PUT` against a
//! single object, signed with a fixed header set. There is no request
//! execution here and no I/O -- [`sign`] takes a request's shape and returns
//! the headers that authenticate it, which is what makes it testable against
//! published vectors.

use eyre::Result;
use reqwest::header::{HeaderName, HeaderValue};
use sha2::{Digest as _, Sha256};
use std::time::{SystemTime, UNIX_EPOCH};
use url::Url;

/// The signing algorithm this module implements.
const ALGORITHM: &str = "AWS4-HMAC-SHA256";
/// SigV4 signs per service; an object store is always `s3`.
const SERVICE: &str = "s3";
/// SHA-256 of the empty string, the payload hash of a body-less request.
const EMPTY_PAYLOAD_SHA256: &str =
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
/// What S3 accepts in place of a payload hash when the body is not read twice.
const UNSIGNED_PAYLOAD: &str = "UNSIGNED-PAYLOAD";

pub(crate) const X_AMZ_DATE: &str = "x-amz-date";
pub(crate) const X_AMZ_CONTENT_SHA256: &str = "x-amz-content-sha256";
pub(crate) const X_AMZ_SECURITY_TOKEN: &str = "x-amz-security-token";

/// Long-lived or session credentials for an S3-compatible service.
///
/// Deliberately not `Debug`: the secret would otherwise reach any log line or
/// panic message that formats a config.
#[derive(Clone)]
pub struct S3Credentials {
    /// Access key identifier.
    pub access_key_id: String,
    /// Secret access key, never logged or formatted.
    pub secret_access_key: String,
    /// Session token accompanying temporary credentials.
    pub session_token: Option<String>,
}

impl S3Credentials {
    /// Read credentials from the environment variables the AWS tools set.
    ///
    /// `None` means the environment does not carry any. These come first in
    /// the credential chain; [`InstanceRoleCredentials`](crate::InstanceRoleCredentials)
    /// is the fallback for a machine that has an EC2 instance role instead.
    /// Anything else that produces temporary credentials, such as an OIDC
    /// exchange, is expected to have exported them here, which is what
    /// `aws-actions/configure-aws-credentials` does on GitHub Actions.
    pub fn from_env() -> Option<Self> {
        Some(Self {
            access_key_id: non_empty_var("AWS_ACCESS_KEY_ID")?,
            secret_access_key: non_empty_var("AWS_SECRET_ACCESS_KEY")?,
            session_token: non_empty_var("AWS_SESSION_TOKEN"),
        })
    }
}

fn non_empty_var(name: &str) -> Option<String> {
    std::env::var(name)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

/// How the payload of a signed request is covered by its signature.
pub(crate) enum PayloadHash {
    /// Hex SHA-256 of the exact bytes being sent.
    Sha256Hex(String),
    /// The body is streamed from a file and deliberately not hashed.
    ///
    /// Hashing would mean reading an artifact twice, up to the 5 GiB single-PUT
    /// ceiling, to protect bytes TLS already covers in transit and the content
    /// address already covers at rest.
    Unsigned,
}

impl PayloadHash {
    /// The hash of a request with no body.
    pub(crate) fn empty() -> Self {
        Self::Sha256Hex(EMPTY_PAYLOAD_SHA256.to_string())
    }

    /// The hash of a body held in memory.
    pub(crate) fn of(bytes: &[u8]) -> Self {
        Self::Sha256Hex(hex::encode(Sha256::digest(bytes)))
    }

    fn as_str(&self) -> &str {
        match self {
            Self::Sha256Hex(hash) => hash,
            Self::Unsigned => UNSIGNED_PAYLOAD,
        }
    }
}

/// Everything about a request that its signature covers besides the payload.
pub(crate) struct SigningContext<'a> {
    pub(crate) credentials: &'a S3Credentials,
    pub(crate) region: &'a str,
    /// Request time. Injected rather than read from the clock so a signature
    /// can be compared against a fixed expected value in tests.
    pub(crate) timestamp: SystemTime,
}

/// Sign a request, returning the headers that authenticate it.
///
/// The signed header set is fixed at `host`, `x-amz-content-sha256`, and
/// `x-amz-date`, plus `x-amz-security-token` when the credentials are
/// temporary. Conditional headers and content types are deliberately left
/// unsigned: S3 requires only `host` and the `x-amz-*` headers to be covered,
/// and a fixed set keeps the canonical request predictable.
pub(crate) fn sign(
    method: &str,
    url: &Url,
    context: &SigningContext<'_>,
    payload: &PayloadHash,
) -> Result<Vec<(HeaderName, HeaderValue)>> {
    let host = url
        .host_str()
        .ok_or_else(|| eyre::eyre!("an S3 endpoint must have a host"))?;
    let host = match url.port() {
        Some(port) => format!("{host}:{port}"),
        None => host.to_string(),
    };
    let (date, date_time) = format_timestamp(context.timestamp)?;
    let payload_hash = payload.as_str();

    let mut headers = vec![
        ("host".to_string(), host),
        (X_AMZ_CONTENT_SHA256.to_string(), payload_hash.to_string()),
        (X_AMZ_DATE.to_string(), date_time.clone()),
    ];
    if let Some(token) = &context.credentials.session_token {
        headers.push((X_AMZ_SECURITY_TOKEN.to_string(), token.clone()));
    }
    headers.sort_by(|left, right| left.0.cmp(&right.0));

    let signed_headers = headers
        .iter()
        .map(|(name, _)| name.as_str())
        .collect::<Vec<_>>()
        .join(";");
    let canonical_headers = headers
        .iter()
        .map(|(name, value)| format!("{name}:{}\n", value.trim()))
        .collect::<String>();

    let canonical_request = format!(
        "{method}\n{}\n{}\n{canonical_headers}\n{signed_headers}\n{payload_hash}",
        canonical_uri(url.path()),
        canonical_query(url),
    );
    let scope = format!("{date}/{}/{SERVICE}/aws4_request", context.region);
    let string_to_sign = format!(
        "{ALGORITHM}\n{date_time}\n{scope}\n{}",
        hex::encode(Sha256::digest(canonical_request.as_bytes()))
    );

    let signature = hex::encode(hmac_sha256(
        &signing_key(
            &context.credentials.secret_access_key,
            &date,
            context.region,
        ),
        string_to_sign.as_bytes(),
    ));
    let authorization = format!(
        "{ALGORITHM} Credential={}/{scope}, SignedHeaders={signed_headers}, Signature={signature}",
        context.credentials.access_key_id
    );

    let mut signed = Vec::with_capacity(headers.len());
    for (name, value) in headers {
        // `host` is set by the HTTP layer from the URL; sending it again would
        // duplicate it in the request.
        if name == "host" {
            continue;
        }
        signed.push((
            HeaderName::from_bytes(name.as_bytes())?,
            header_value(&name, &value)?,
        ));
    }
    signed.push((
        reqwest::header::AUTHORIZATION,
        header_value("authorization", &authorization)?,
    ));
    Ok(signed)
}

fn header_value(name: &str, value: &str) -> Result<HeaderValue> {
    let mut header = HeaderValue::from_str(value)?;
    if name == X_AMZ_SECURITY_TOKEN || name == "authorization" {
        header.set_sensitive(true);
    }
    Ok(header)
}

/// Derive the request's signing key from the secret, scoped to date and region.
///
/// The scoping is what keeps a leaked signature from being replayed against
/// another day or another region.
fn signing_key(secret: &str, date: &str, region: &str) -> Vec<u8> {
    let date_key = hmac_sha256(format!("AWS4{secret}").as_bytes(), date.as_bytes());
    let region_key = hmac_sha256(&date_key, region.as_bytes());
    let service_key = hmac_sha256(&region_key, SERVICE.as_bytes());
    hmac_sha256(&service_key, b"aws4_request")
}

/// HMAC-SHA256 (RFC 2104).
///
/// Hand-written over the SHA-256 this crate already depends on. Only signatures
/// are produced here, never verified, so there is nothing to compare in
/// constant time.
fn hmac_sha256(key: &[u8], message: &[u8]) -> Vec<u8> {
    const BLOCK_BYTES: usize = 64;
    let mut block = [0_u8; BLOCK_BYTES];
    if key.len() > BLOCK_BYTES {
        block[..32].copy_from_slice(&Sha256::digest(key));
    } else {
        block[..key.len()].copy_from_slice(key);
    }
    let mut inner = Sha256::new();
    inner.update(block.map(|byte| byte ^ 0x36));
    inner.update(message);
    let mut outer = Sha256::new();
    outer.update(block.map(|byte| byte ^ 0x5c));
    outer.update(inner.finalize());
    outer.finalize().to_vec()
}

/// The request path as the canonical request states it.
///
/// S3 is the one service that encodes the path exactly once rather than twice,
/// and the caller passes [`Url::path`], which is already encoded. Encoding it
/// again here would sign `%2520` for a key the request line spells `%20`, and
/// every such key would fail to authenticate.
fn canonical_uri(path: &str) -> String {
    if path.is_empty() {
        "/".to_string()
    } else {
        path.to_string()
    }
}

/// Encode a query string in the canonical form: sorted, and encoded per value.
///
/// tuist_cargo_cache addresses objects by path alone, so this is empty in practice. It exists
/// so that adding a query parameter later cannot silently break signing.
fn canonical_query(url: &Url) -> String {
    let mut pairs = url
        .query_pairs()
        .map(|(key, value)| (uri_encode(&key), uri_encode(&value)))
        .collect::<Vec<_>>();
    pairs.sort();
    pairs
        .iter()
        .map(|(key, value)| format!("{key}={value}"))
        .collect::<Vec<_>>()
        .join("&")
}

/// Percent-encode everything outside AWS's unreserved set, with uppercase hex.
fn uri_encode(value: &str) -> String {
    let mut encoded = String::with_capacity(value.len());
    for byte in value.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'.' | b'_' | b'~') {
            encoded.push(byte as char);
        } else {
            encoded.push_str(&format!("%{byte:02X}"));
        }
    }
    encoded
}

/// Format a request time as the `YYYYMMDD` scope date and `YYYYMMDDTHHMMSSZ`
/// stamp SigV4 requires.
fn format_timestamp(timestamp: SystemTime) -> Result<(String, String)> {
    let seconds = timestamp
        .duration_since(UNIX_EPOCH)
        .map_err(|_| eyre::eyre!("system clock is before the Unix epoch"))?
        .as_secs();
    let days = (seconds / 86_400) as i64;
    let time_of_day = seconds % 86_400;
    let (year, month, day) = civil_from_days(days);
    Ok((
        format!("{year:04}{month:02}{day:02}"),
        format!(
            "{year:04}{month:02}{day:02}T{:02}{:02}{:02}Z",
            time_of_day / 3_600,
            (time_of_day % 3_600) / 60,
            time_of_day % 60
        ),
    ))
}

/// Convert a count of days since the Unix epoch to a civil date.
///
/// Howard Hinnant's `civil_from_days`, which shifts the year to start in March
/// so that the leap day lands at the end of a 400-year era and needs no special
/// case. Used instead of a date library because SigV4 needs exactly this and
/// nothing else about calendars.
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let day_of_era = z - era * 146_097;
    let year_of_era =
        (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let year = year_of_era + era * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let shifted_month = (5 * day_of_year + 2) / 153;
    let day = (day_of_year - (153 * shifted_month + 2) / 5 + 1) as u32;
    let month = if shifted_month < 10 {
        shifted_month + 3
    } else {
        shifted_month - 9
    } as u32;
    (if month <= 2 { year + 1 } else { year }, month, day)
}

/// A `SystemTime` a fixed number of seconds after the Unix epoch.
#[cfg(test)]
fn epoch_plus(seconds: u64) -> SystemTime {
    UNIX_EPOCH + std::time::Duration::from_secs(seconds)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn credentials() -> S3Credentials {
        S3Credentials {
            access_key_id: "AKIDEXAMPLE".into(),
            secret_access_key: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY".into(),
            session_token: None,
        }
    }

    /// RFC 4231 test case 1.
    #[test]
    fn hmac_matches_rfc_4231() {
        assert_eq!(
            hex::encode(hmac_sha256(&[0x0b; 20], b"Hi There")),
            "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
        );
    }

    /// RFC 4231 test case 3, whose message is longer than one hash block.
    #[test]
    fn hmac_matches_rfc_4231_multi_block_message() {
        assert_eq!(
            hex::encode(hmac_sha256(&[0xaa; 20], &[0xdd; 50])),
            "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe"
        );
    }

    /// RFC 4231 test case 6, whose key is longer than one hash block and is
    /// therefore replaced by its own digest.
    #[test]
    fn hmac_hashes_keys_longer_than_a_block() {
        assert_eq!(
            hex::encode(hmac_sha256(
                &[0xaa; 131],
                b"Test Using Larger Than Block-Size Key - Hash Key First"
            )),
            "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"
        );
    }

    #[test]
    fn empty_payload_constant_is_the_hash_of_no_bytes() {
        let PayloadHash::Sha256Hex(hash) = PayloadHash::empty() else {
            panic!("empty payload is hashed");
        };
        assert_eq!(hash, hex::encode(Sha256::digest(b"")));
    }

    #[test]
    fn timestamps_format_as_sigv4_expects() {
        assert_eq!(
            format_timestamp(epoch_plus(0)).unwrap(),
            ("19700101".to_string(), "19700101T000000Z".to_string())
        );
        // 2015-08-30T12:36:00Z, the instant AWS's own signing examples use.
        assert_eq!(
            format_timestamp(epoch_plus(1_440_938_160)).unwrap(),
            ("20150830".to_string(), "20150830T123600Z".to_string())
        );
        // 2024-02-29T23:59:59Z: a leap day, at the end of the day.
        assert_eq!(
            format_timestamp(epoch_plus(1_709_251_199)).unwrap(),
            ("20240229".to_string(), "20240229T235959Z".to_string())
        );
        // 2100-03-01T00:00:00Z: past a century that is not a leap year.
        assert_eq!(
            format_timestamp(epoch_plus(4_107_542_400)).unwrap(),
            ("21000301".to_string(), "21000301T000000Z".to_string())
        );
    }

    #[test]
    fn paths_are_signed_exactly_as_the_request_spells_them() {
        assert_eq!(
            canonical_uri("/ns/v1/blobs/blake3/ab/12"),
            "/ns/v1/blobs/blake3/ab/12"
        );
        assert_eq!(canonical_uri(""), "/");
        // `Url::path` has already encoded the path. Encoding it a second time
        // would sign a different key than the one the request asks for.
        assert_eq!(canonical_uri("/a%20b"), "/a%20b");
    }

    #[test]
    fn query_values_are_encoded_with_the_unreserved_set() {
        assert_eq!(uri_encode("-._~"), "-._~");
        assert_eq!(uri_encode("a b"), "a%20b");
        assert_eq!(uri_encode("c+d/e"), "c%2Bd%2Fe");
    }

    #[test]
    fn query_strings_are_sorted_and_encoded() {
        let url: Url = "https://bucket.example.com/key?b=2&a=1&c=with%20space"
            .parse()
            .unwrap();
        assert_eq!(canonical_query(&url), "a=1&b=2&c=with%20space");
        let bare: Url = "https://bucket.example.com/key".parse().unwrap();
        assert_eq!(canonical_query(&bare), "");
    }

    /// Pinned against an independent implementation of SigV4 (Python's `hmac`
    /// and `hashlib` driving the same canonical request), so a change in this
    /// module's own arithmetic cannot move the expected value with it.
    #[test]
    fn signs_a_get_the_way_the_specification_does() {
        let url: Url = "https://examplebucket.s3.amazonaws.com/test.txt"
            .parse()
            .unwrap();
        let context = SigningContext {
            credentials: &credentials(),
            region: "us-east-1",
            timestamp: epoch_plus(1_440_938_160),
        };

        let headers = sign("GET", &url, &context, &PayloadHash::empty()).unwrap();

        let authorization = header(&headers, "authorization");
        assert_eq!(
            authorization,
            "AWS4-HMAC-SHA256 \
             Credential=AKIDEXAMPLE/20150830/us-east-1/s3/aws4_request, \
             SignedHeaders=host;x-amz-content-sha256;x-amz-date, \
             Signature=bbfdf4d3c3eab24da182f8f790e0c7d8e2a20658191717a6546076effa9f5a5e"
        );
        assert_eq!(header(&headers, X_AMZ_DATE), "20150830T123600Z");
        assert_eq!(header(&headers, X_AMZ_CONTENT_SHA256), EMPTY_PAYLOAD_SHA256);
        assert!(!headers.iter().any(|(name, _)| name.as_str() == "host"));
    }

    #[test]
    fn temporary_credentials_sign_and_send_their_session_token() {
        let url: Url = "https://examplebucket.s3.amazonaws.com/test.txt"
            .parse()
            .unwrap();
        let credentials = S3Credentials {
            session_token: Some("session-token".into()),
            ..credentials()
        };
        let context = SigningContext {
            credentials: &credentials,
            region: "us-east-1",
            timestamp: epoch_plus(1_440_938_160),
        };

        let headers = sign("PUT", &url, &context, &PayloadHash::Unsigned).unwrap();

        assert_eq!(
            header(&headers, "authorization"),
            "AWS4-HMAC-SHA256 \
             Credential=AKIDEXAMPLE/20150830/us-east-1/s3/aws4_request, \
             SignedHeaders=host;x-amz-content-sha256;x-amz-date;x-amz-security-token, \
             Signature=37e8be08e60e6a292f591b6a462e7fb96436b4c1925f6978e8869a7c4577e12f"
        );
        assert_eq!(header(&headers, X_AMZ_SECURITY_TOKEN), "session-token");
        assert_eq!(header(&headers, X_AMZ_CONTENT_SHA256), UNSIGNED_PAYLOAD);
    }

    #[test]
    fn a_signature_covers_the_payload_the_method_and_the_key() {
        let url: Url = "https://examplebucket.s3.amazonaws.com/test.txt"
            .parse()
            .unwrap();
        let other: Url = "https://examplebucket.s3.amazonaws.com/other.txt"
            .parse()
            .unwrap();
        let credentials = credentials();
        let signature = |method: &str, url: &Url, region: &str, payload: PayloadHash| {
            let context = SigningContext {
                credentials: &credentials,
                region,
                timestamp: epoch_plus(1_440_938_160),
            };
            header(
                &sign(method, url, &context, &payload).unwrap(),
                "authorization",
            )
            .to_string()
        };

        let baseline = signature("GET", &url, "us-east-1", PayloadHash::empty());
        for (what, other) in [
            (
                "method",
                signature("PUT", &url, "us-east-1", PayloadHash::empty()),
            ),
            (
                "key",
                signature("GET", &other, "us-east-1", PayloadHash::empty()),
            ),
            (
                "region",
                signature("GET", &url, "eu-west-1", PayloadHash::empty()),
            ),
            (
                "payload",
                signature("GET", &url, "us-east-1", PayloadHash::of(b"body")),
            ),
            (
                "unsigned payload",
                signature("GET", &url, "us-east-1", PayloadHash::Unsigned),
            ),
        ] {
            assert_ne!(baseline, other, "signature ignores the request's {what}");
        }
    }

    fn header<'a>(headers: &'a [(HeaderName, HeaderValue)], name: &str) -> &'a str {
        headers
            .iter()
            .find(|(header, _)| header.as_str() == name)
            .map(|(_, value)| value.to_str().unwrap())
            .unwrap_or_else(|| panic!("missing header {name}"))
    }
}
