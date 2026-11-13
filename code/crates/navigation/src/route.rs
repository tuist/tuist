use percent_encoding::{AsciiSet, NON_ALPHANUMERIC, percent_decode_str, utf8_percent_encode};
use url::Url;

const SEGMENT: &AsciiSet = &NON_ALPHANUMERIC
    .remove(b'-')
    .remove(b'.')
    .remove(b'_')
    .remove(b'~');

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Preview {
    pub account: String,
    pub project: String,
    pub id: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Route {
    Previews,
    Profile,
    Preview(Preview),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RouteError {
    InvalidUrl,
    DifferentServer,
}

impl std::fmt::Display for RouteError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::InvalidUrl => "This link is not a supported Tuist destination.",
            Self::DifferentServer => "This link belongs to a different Tuist server.",
        })
    }
}

impl std::error::Error for RouteError {}

impl Route {
    pub fn parse(value: &str, server: &Url) -> Result<Self, RouteError> {
        let (url, raw_path) = parse_url(value)?;
        if url.fragment().is_some() {
            return Err(RouteError::InvalidUrl);
        }
        let parts = segments(raw_path)?;
        let detail = if url.scheme() == "tuist" {
            if !url
                .host_str()
                .is_some_and(|host| host.eq_ignore_ascii_case("app"))
                || url.port().is_some()
            {
                return Err(RouteError::InvalidUrl);
            }
            if parts == ["previews"] || parts == ["profile"] {
                if url.query().is_some() {
                    return Err(RouteError::InvalidUrl);
                }
                return Ok(if parts[0] == "previews" {
                    Self::Previews
                } else {
                    Self::Profile
                });
            }
            let target = match url.query() {
                None => "https://tuist.dev".to_string(),
                Some(query) => {
                    let (key, value) = query.split_once('=').ok_or(RouteError::InvalidUrl)?;
                    if query.contains('&') || value.contains('=') || decode(key)? != "server" {
                        return Err(RouteError::InvalidUrl);
                    }
                    decode(value)?
                }
            };
            if server_base(&target)? != server_base(server.as_str())? {
                return Err(RouteError::DifferentServer);
            }
            parts
        } else {
            if url.query().is_some() || !same_origin(&url, server) {
                return Err(RouteError::DifferentServer);
            }
            let base = server_base(server.as_str())?;
            let base_parts = segments(base.path().trim_end_matches('/')).unwrap_or_default();
            if !parts.starts_with(&base_parts) {
                return Err(RouteError::DifferentServer);
            }
            parts[base_parts.len()..].to_vec()
        };
        if detail.len() != 4 || detail[2] != "previews" || detail[3] == "latest" {
            return Err(RouteError::InvalidUrl);
        }
        Ok(Self::Preview(Preview {
            account: detail[0].clone(),
            project: detail[1].clone(),
            id: detail[3].clone(),
        }))
    }

    pub fn url(&self, server: &Url) -> Result<Url, RouteError> {
        match self {
            Self::Previews => Ok(Url::parse("tuist://app/previews").unwrap()),
            Self::Profile => Ok(Url::parse("tuist://app/profile").unwrap()),
            Self::Preview(preview) => {
                let base = server_base(server.as_str())?;
                Url::parse(&format!(
                    "{}{}",
                    base.as_str().trim_end_matches('/'),
                    preview.path()?
                ))
                .map_err(|_| RouteError::InvalidUrl)
            }
        }
    }

    pub fn handoff_url(&self, server: &Url) -> Result<Url, RouteError> {
        let Self::Preview(preview) = self else {
            return self.url(server);
        };
        let base = server_base(server.as_str())?;
        Url::parse(&format!(
            "tuist://app{}?server={}",
            preview.path()?,
            encode(base.as_str().trim_end_matches('/'))
        ))
        .map_err(|_| RouteError::InvalidUrl)
    }

    pub fn is_server_web_url(value: &str, server: &Url) -> bool {
        let Ok((url, path)) = parse_url(value) else {
            return false;
        };
        let Ok(base) = server_base(server.as_str()) else {
            return false;
        };
        let path = path.trim_end_matches('/');
        let base_path = base.path().trim_end_matches('/');
        same_origin(&url, &base)
            && (path == base_path || path.starts_with(&format!("{base_path}/")))
            && (path.is_empty() || segments(path).is_ok())
    }
}

impl Preview {
    fn path(&self) -> Result<String, RouteError> {
        let parts = [&self.account[..], &self.project, "previews", &self.id];
        if parts.iter().any(|part| !valid_segment(part)) || self.id == "latest" {
            return Err(RouteError::InvalidUrl);
        }
        Ok(format!("/{}", parts.map(encode).join("/")))
    }
}

fn encode(value: &str) -> String {
    utf8_percent_encode(value, SEGMENT).to_string()
}

fn decode(value: &str) -> Result<String, RouteError> {
    for (index, byte) in value.bytes().enumerate() {
        if byte == b'%'
            && !value
                .as_bytes()
                .get(index + 1..index + 3)
                .is_some_and(|pair| pair.iter().all(u8::is_ascii_hexdigit))
        {
            return Err(RouteError::InvalidUrl);
        }
    }
    percent_decode_str(value)
        .decode_utf8()
        .map(|s| s.into_owned())
        .map_err(|_| RouteError::InvalidUrl)
}

fn valid_segment(value: &str) -> bool {
    !value.is_empty()
        && value != "."
        && value != ".."
        && !value
            .chars()
            .any(|c| c == '/' || c == '\\' || c.is_whitespace() || c.is_control())
}

fn segments(path: &str) -> Result<Vec<String>, RouteError> {
    path.strip_prefix('/')
        .ok_or(RouteError::InvalidUrl)?
        .split('/')
        .map(|part| {
            let value = decode(part)?;
            if valid_segment(&value) {
                Ok(value)
            } else {
                Err(RouteError::InvalidUrl)
            }
        })
        .collect()
}

// Inspect the raw path before Url normalizes traversal and backslashes.
fn parse_url(value: &str) -> Result<(Url, &str), RouteError> {
    if value
        .chars()
        .any(|c| c.is_whitespace() || c.is_control() || c == '\\')
    {
        return Err(RouteError::InvalidUrl);
    }
    let (_, rest) = value.split_once("://").ok_or(RouteError::InvalidUrl)?;
    let authority_end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    if rest[..authority_end].contains('@') {
        return Err(RouteError::InvalidUrl);
    }
    let path = rest[authority_end..].split(['?', '#']).next().unwrap_or("");
    let url = Url::parse(value).map_err(|_| RouteError::InvalidUrl)?;
    if url.host_str().is_none() || url.port() == Some(0) {
        return Err(RouteError::InvalidUrl);
    }
    Ok((url, path))
}

fn same_origin(url: &Url, server: &Url) -> bool {
    matches!(url.scheme(), "http" | "https") && url.origin() == server.origin()
}

fn server_base(value: &str) -> Result<Url, RouteError> {
    let (url, path) = parse_url(value)?;
    if !matches!(url.scheme(), "http" | "https")
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return Err(RouteError::InvalidUrl);
    }
    let path = path.trim_end_matches('/');
    let parts = if path.is_empty() {
        vec![]
    } else {
        segments(path)?
    };
    let mut base = url;
    base.set_path(&format!(
        "/{}",
        parts
            .iter()
            .map(|part| encode(part))
            .collect::<Vec<_>>()
            .join("/")
    ));
    Ok(base)
}
