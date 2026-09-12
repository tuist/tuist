use std::{collections::BTreeMap, time::Duration};

use base64::{Engine as _, engine::general_purpose::STANDARD};
use bazel_remote_apis::build::bazel::remote::asset::v1::FetchBlobRequest;
use reqwest::{
    Url,
    header::{HeaderMap, HeaderName, HeaderValue},
};
use sha2::{Digest as _, Sha256, Sha384, Sha512};
use tonic::Status;

pub(super) const MAX_REQUEST_BYTES: usize = 64 * 1024;
pub(super) const MAX_FETCH_TIME: Duration = Duration::from_secs(600);

pub(super) struct FetchSpec {
    pub uris: Vec<Url>,
    pub headers: Vec<HeaderMap>,
    pub keys: Vec<String>,
    pub timeout: Duration,
    pub oldest: u128,
    pub checksum: Option<Checksum>,
}

pub(super) enum Checksum {
    Sha256(Vec<u8>),
    Sha384(Vec<u8>),
    Sha512(Vec<u8>),
}

impl Checksum {
    fn parse(value: &str) -> Result<Self, Status> {
        let (algorithm, encoded) = value
            .split_once('-')
            .ok_or_else(|| Status::invalid_argument("checksum.sri must contain an SRI checksum"))?;
        let bytes = STANDARD
            .decode(encoded)
            .map_err(|_| Status::invalid_argument("checksum.sri contains invalid base64"))?;
        match (algorithm, bytes.len()) {
            ("sha256", 32) => Ok(Self::Sha256(bytes)),
            ("sha384", 48) => Ok(Self::Sha384(bytes)),
            ("sha512", 64) => Ok(Self::Sha512(bytes)),
            _ => Err(Status::invalid_argument(
                "checksum.sri supports SHA-256, SHA-384 and SHA-512",
            )),
        }
    }

    pub fn matches(&self, sha256: &Sha256, sha384: &Sha384, sha512: &Sha512) -> bool {
        match self {
            Self::Sha256(expected) => sha256.clone().finalize().as_slice() == expected,
            Self::Sha384(expected) => sha384.clone().finalize().as_slice() == expected,
            Self::Sha512(expected) => sha512.clone().finalize().as_slice() == expected,
        }
    }
}

impl FetchSpec {
    pub fn parse(request: &FetchBlobRequest) -> Result<Self, Status> {
        if request.uris.is_empty() || request.uris.len() > 16 || request.qualifiers.len() > 64 {
            return Err(Status::invalid_argument(
                "fetch requires 1–16 URIs and at most 64 qualifiers",
            ));
        }
        let timeout = match request.timeout.as_ref() {
            Some(t) if t.seconds < 0 || !(0..1_000_000_000).contains(&t.nanos) => {
                return Err(Status::invalid_argument("invalid fetch timeout"));
            }
            Some(t) if t.seconds != 0 || t.nanos != 0 => {
                Duration::new(t.seconds as u64, t.nanos as u32).min(MAX_FETCH_TIME)
            }
            _ => MAX_FETCH_TIME,
        };
        let oldest = match request.oldest_content_accepted.as_ref() {
            Some(t) if !(0..1_000_000_000).contains(&t.nanos) => {
                return Err(Status::invalid_argument("invalid oldest_content_accepted"));
            }
            Some(t) if t.seconds >= 0 => t.seconds as u128 * 1_000_000_000 + t.nanos as u128,
            _ => 0,
        };
        let uris = request
            .uris
            .iter()
            .map(|uri| {
                let url =
                    Url::parse(uri).map_err(|_| Status::invalid_argument("invalid asset URI"))?;
                validate_url(&url)?;
                Ok(url)
            })
            .collect::<Result<Vec<_>, Status>>()?;
        let mut qualifiers = BTreeMap::new();
        let mut common = HeaderMap::new();
        let mut headers = vec![HeaderMap::new(); uris.len()];
        let mut checksum = None;
        for qualifier in &request.qualifiers {
            if qualifiers
                .insert(qualifier.name.clone(), qualifier.value.clone())
                .is_some()
            {
                return Err(Status::invalid_argument("qualifier names must be unique"));
            }
            match qualifier.name.as_str() {
                "checksum.sri" => checksum = Some(Checksum::parse(&qualifier.value)?),
                "bazel.canonical_id" => {}
                name if name.starts_with("http_header:") => {
                    insert_header(&mut common, &name[12..], &qualifier.value)?;
                }
                name if name.starts_with("http_header_url:") => {
                    let (index, name) = name[16..].split_once(':').ok_or_else(|| {
                        Status::invalid_argument("invalid URI-specific HTTP header")
                    })?;
                    let index = index
                        .parse::<usize>()
                        .ok()
                        .filter(|i| *i < headers.len())
                        .ok_or_else(|| {
                            Status::invalid_argument("HTTP header URI index is out of range")
                        })?;
                    insert_header(&mut headers[index], name, &qualifier.value)?;
                }
                _ => {
                    return Err(Status::invalid_argument(
                        "unsupported remote asset qualifier",
                    ));
                }
            }
        }
        for specific in &mut headers {
            let mut merged = common.clone();
            merged.extend(specific.clone());
            *specific = merged;
        }
        // Persist only hashes of URLs and headers, never signed URLs or origin credentials.
        // URI-specific headers are keyed by their effective value, not their index in a mirror list.
        let keys = request
            .uris
            .iter()
            .zip(&headers)
            .map(|(uri, headers)| {
                let headers = headers
                    .iter()
                    .map(|(k, v)| (k.as_str(), v.as_bytes()))
                    .collect::<BTreeMap<_, _>>();
                let identity = serde_json::to_vec(&(
                    uri,
                    qualifiers.get("checksum.sri"),
                    qualifiers.get("bazel.canonical_id"),
                    headers,
                ))
                .expect("serializable asset identity");
                format!("remote-asset/v1/{}", hex::encode(Sha256::digest(identity)))
            })
            .collect();
        Ok(Self {
            uris,
            headers,
            keys,
            timeout,
            oldest,
            checksum,
        })
    }
}

pub(super) fn validate_url(url: &Url) -> Result<(), Status> {
    if !matches!(url.scheme(), "http" | "https")
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.fragment().is_some()
    {
        return Err(Status::invalid_argument(
            "asset URI must be HTTP(S) without userinfo or fragment",
        ));
    }
    Ok(())
}

fn insert_header(headers: &mut HeaderMap, name: &str, value: &str) -> Result<(), Status> {
    let name = HeaderName::from_bytes(name.as_bytes())
        .map_err(|_| Status::invalid_argument("invalid HTTP header name"))?;
    if matches!(
        name.as_str(),
        "host"
            | "connection"
            | "transfer-encoding"
            | "content-length"
            | "proxy-authorization"
            | "proxy-connection"
            | "upgrade"
            | "te"
            | "trailer"
            | "range"
            | "if-range"
            | "if-none-match"
            | "if-modified-since"
    ) || (name == "accept-encoding" && value != "identity")
    {
        return Err(Status::invalid_argument(
            "HTTP header is not supported for asset downloads",
        ));
    }
    let value = HeaderValue::from_str(value)
        .map_err(|_| Status::invalid_argument("invalid HTTP header value"))?;
    headers.insert(name, value);
    Ok(())
}
