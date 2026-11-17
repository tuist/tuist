//! URL routing shared by every edge. Routes contain identifiers, never API models.
use serde::Serialize;
use url::Url;

const INVALID: &str = "This link is not a supported Guild destination";
const WRONG_SERVER: &str = "This link belongs to a different Guild server";

/// The complete addressable screen catalog. Adding a screen starts here.
pub const ROUTES: &[&str] = &["/threads", "/threads/{id}", "/profile"];

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Destination {
    Threads,
    Thread(String),
    Profile,
}

impl Destination {
    pub fn path(&self) -> String {
        match self {
            Self::Threads => "/threads".into(),
            Self::Thread(id) => format!("/threads/{id}"),
            Self::Profile => "/profile".into(),
        }
    }

    fn parse(path: &str) -> Result<Self, &'static str> {
        match path {
            "/threads" => Ok(Self::Threads),
            "/profile" => Ok(Self::Profile),
            _ => {
                let id = path.strip_prefix("/threads/").ok_or(INVALID)?;
                if id.len() != 36
                    || !id.bytes().enumerate().all(|(i, b)| {
                        if [8, 13, 18, 23].contains(&i) {
                            b == b'-'
                        } else {
                            b.is_ascii_hexdigit()
                        }
                    })
                {
                    return Err(INVALID);
                }
                Ok(Self::Thread(id.to_ascii_lowercase()))
            }
        }
    }
}

#[derive(Clone, Debug)]
pub struct Link {
    pub destination: Destination,
    server: Option<Url>,
}

impl Link {
    pub fn parse(value: &str) -> Result<Self, &'static str> {
        if value
            .chars()
            .any(|c| c.is_whitespace() || c.is_control() || c == '\\')
        {
            return Err(INVALID);
        }
        if value.starts_with('/') {
            return Ok(Self {
                destination: Destination::parse(value)?,
                server: None,
            });
        }
        let url = Url::parse(value).map_err(|_| INVALID)?;
        if !url.username().is_empty() || url.password().is_some() || url.fragment().is_some() {
            return Err(INVALID);
        }
        // Inspect the original path: Url removes dot segments before exposing path().
        let raw = value.split_once("://").ok_or(INVALID)?.1;
        if raw
            .split(['/', '?', '#'])
            .next()
            .unwrap_or("")
            .contains('@')
        {
            return Err(INVALID);
        }
        let path = raw.find('/').map(|i| &raw[i..]).unwrap_or("");
        let path = path.split(['?', '#']).next().unwrap_or("");
        if path.contains('%') || path.split('/').any(|p| matches!(p, "." | "..")) {
            return Err(INVALID);
        }
        let (destination, server) = if url.scheme() == "tuist-guild" {
            if url.host_str() != Some("app") || url.port().is_some() {
                return Err(INVALID);
            }
            let pairs: Vec<_> = url.query_pairs().collect();
            let server = match pairs.as_slice() {
                [] if url.query().is_none() => "https://tuist.dev".into(),
                [(key, value)] if key == "server" => value.to_string(),
                _ => return Err(INVALID),
            };
            (Destination::parse(path)?, base(&server)?)
        } else {
            if url.query().is_some() {
                return Err(INVALID);
            }
            let (prefix, suffix) = path.rsplit_once("/guild/").ok_or(INVALID)?;
            let destination = Destination::parse(&format!("/{suffix}"))?;
            let mut server = url.clone();
            server.set_path(prefix);
            (destination, base(server.as_str())?)
        };
        Ok(Self {
            destination,
            server: Some(server),
        })
    }

    pub fn resolve(&self, server: &Url) -> Result<Destination, &'static str> {
        if let Some(expected) = &self.server
            && *expected != base(server.as_str())?
        {
            return Err(WRONG_SERVER);
        }
        Ok(self.destination.clone())
    }
}

fn base(value: &str) -> Result<Url, &'static str> {
    let mut url = Url::parse(value).map_err(|_| INVALID)?;
    if !(url.scheme() == "https"
        || (url.scheme() == "http"
            && matches!(url.host_str(), Some("localhost" | "127.0.0.1" | "[::1]"))))
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
        || value
            .chars()
            .any(|c| c.is_whitespace() || c.is_control() || c == '\\')
    {
        return Err(INVALID);
    }
    let path = url.path().trim_end_matches('/').to_owned();
    url.set_path(&path);
    Ok(url)
}

#[derive(Clone, Debug, Serialize)]
pub struct Navigation {
    pub tab: &'static str,
    pub thread_id: Option<String>,
    pub path: String,
    pub revision: u64,
    #[serde(skip)]
    pending: Option<Link>,
}

impl Default for Navigation {
    fn default() -> Self {
        Self {
            tab: "threads",
            thread_id: None,
            path: "/threads".into(),
            revision: 0,
            pending: None,
        }
    }
}

impl Navigation {
    pub fn receive(&mut self, value: &str, server: Option<&Url>) -> Result<(), &'static str> {
        let link = Link::parse(value)?;
        if let Some(server) = server {
            self.navigate(link.resolve(server)?);
        } else {
            self.pending = Some(link);
        }
        Ok(())
    }

    pub fn resume(&mut self, server: &Url) -> Result<(), &'static str> {
        if let Some(link) = self.pending.take() {
            self.navigate(link.resolve(server)?);
        }
        Ok(())
    }

    pub fn navigate(&mut self, destination: Destination) {
        match &destination {
            Destination::Profile => self.tab = "profile",
            Destination::Threads => {
                self.tab = "threads";
                self.thread_id = None;
            }
            Destination::Thread(id) => {
                self.tab = "threads";
                self.thread_id = Some(id.clone());
            }
        }
        self.changed();
    }

    pub fn select(&mut self, tab: &str) -> Result<(), &'static str> {
        self.tab = match tab {
            "threads" => "threads",
            "profile" => "profile",
            _ => return Err(INVALID),
        };
        self.changed();
        Ok(())
    }

    pub fn reset(&mut self) {
        let revision = self.revision + 1;
        *self = Self {
            revision,
            ..Self::default()
        };
    }

    fn changed(&mut self) {
        self.path = if self.tab == "profile" {
            "/profile".into()
        } else {
            self.thread_id
                .as_ref()
                .map(|id| format!("/threads/{id}"))
                .unwrap_or("/threads".into())
        };
        self.revision += 1;
    }
}
