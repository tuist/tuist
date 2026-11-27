//! URL routing shared by every edge. Routes contain identifiers, never API models.
use serde::Serialize;
use url::Url;

const INVALID: &str = "This link is not a supported Luft destination";
const WRONG_SERVER: &str = "This link belongs to a different Luft server";

/// The complete addressable screen catalog. Adding a screen starts here.
pub const ROUTES: &[&str] = &[
    "/threads",
    "/threads/new",
    "/threads/new/dictation",
    "/threads/{id}",
    "/threads/{id}/snooze",
    "/lounges",
    "/lounges/{id}",
    "/dms",
    "/dms/{id}",
    "/profile",
    "/ops",
];

/// The tabs that hold a stack of one conversation, in catalog order.
const STACKS: [&str; 3] = ["threads", "lounges", "dms"];

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Destination {
    /// A tab's root (`threads`, `lounges` or `dms`), or one conversation in it.
    List(&'static str),
    Conversation(&'static str, String),
    /// A thread with its snooze choices open over it.
    Snooze(String),
    /// Start conversation on the Threads root; `dictate` starts with dictation.
    NewThread {
        dictate: bool,
    },
    Profile,
    /// Collections and Releases.
    Ops,
}

impl Destination {
    pub const THREADS: Self = Self::List("threads");

    pub fn path(&self) -> String {
        match self {
            Self::List(tab) => format!("/{tab}"),
            Self::Conversation(tab, id) => format!("/{tab}/{id}"),
            Self::Snooze(id) => format!("/threads/{id}/snooze"),
            Self::NewThread { dictate: false } => "/threads/new".into(),
            Self::NewThread { dictate: true } => "/threads/new/dictation".into(),
            Self::Profile => "/profile".into(),
            Self::Ops => "/ops".into(),
        }
    }

    fn parse(path: &str) -> Result<Self, &'static str> {
        match path {
            "/profile" => return Ok(Self::Profile),
            "/ops" => return Ok(Self::Ops),
            "/threads/new" => return Ok(Self::NewThread { dictate: false }),
            "/threads/new/dictation" => return Ok(Self::NewThread { dictate: true }),
            _ => {}
        }
        if let Some(thread) = path
            .strip_prefix("/threads/")
            .and_then(|p| p.strip_suffix("/snooze"))
        {
            return match Self::parse(&format!("/threads/{thread}"))? {
                Self::Conversation(_, id) => Ok(Self::Snooze(id)),
                _ => Err(INVALID),
            };
        }
        let rest = path.strip_prefix('/').ok_or(INVALID)?;
        let (tab, id) = rest.split_once('/').unwrap_or((rest, ""));
        let tab = STACKS.into_iter().find(|t| *t == tab).ok_or(INVALID)?;
        if id.is_empty() && !rest.ends_with('/') {
            return Ok(Self::List(tab));
        }
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
        Ok(Self::Conversation(tab, id.to_ascii_lowercase()))
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
        let (destination, server) = if url.scheme() == "luft" {
            if url.host_str() != Some("app") || url.port().is_some() {
                return Err(INVALID);
            }
            let pairs: Vec<_> = url.query_pairs().collect();
            let server = match pairs.as_slice() {
                [] if url.query().is_none() => "https://luft.work".into(),
                [(key, value)] if key == "server" => value.to_string(),
                _ => return Err(INVALID),
            };
            (Destination::parse(path)?, base(&server)?)
        } else {
            if url.query().is_some() {
                return Err(INVALID);
            }
            let (prefix, suffix) = path.rsplit_once("/luft/").ok_or(INVALID)?;
            let destination = Destination::parse(&format!("/{suffix}"))?;
            let mut server = url.clone();
            server.set_path(prefix);
            (destination, base(server.as_str())?)
        };
        // Dictation opens the microphone, so it needs the person's own action, such as an
        // App Shortcut, never a link another app or web page can open.
        if destination == (Destination::NewThread { dictate: true }) {
            return Err(INVALID);
        }
        Ok(Self {
            destination,
            server: Some(server),
        })
    }

    /// The server a scoped link belongs to; `None` for an internal path.
    pub fn server(&self) -> Option<&Url> {
        self.server.as_ref()
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
    /// Each tab's open conversation, kept while another tab is selected.
    pub thread_id: Option<String>,
    pub lounge_id: Option<String>,
    pub dm_id: Option<String>,
    /// `text` or `dictation` while Start conversation is open on the Threads root.
    pub compose: Option<&'static str>,
    /// Whether the open thread's snooze choices show over it.
    pub snooze: bool,
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
            lounge_id: None,
            dm_id: None,
            compose: None,
            snooze: false,
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
        self.compose = None;
        self.snooze = false;
        match destination {
            Destination::Profile => self.tab = "profile",
            Destination::Ops => self.tab = "ops",
            Destination::List(tab) => {
                self.tab = tab;
                *self.stack(tab) = None;
            }
            Destination::Conversation(tab, id) => {
                self.tab = tab;
                *self.stack(tab) = Some(id);
            }
            Destination::Snooze(id) => {
                self.tab = "threads";
                self.thread_id = Some(id);
                self.snooze = true;
            }
            Destination::NewThread { dictate } => {
                self.tab = "threads";
                self.thread_id = None;
                self.compose = Some(if dictate { "dictation" } else { "text" });
            }
        }
        self.changed();
    }

    /// Returns from the selected tab's conversation to its list.
    pub fn back(&mut self) {
        let tab = if matches!(self.tab, "profile" | "ops") {
            "threads"
        } else {
            self.tab
        };
        self.navigate(Destination::List(tab));
    }

    pub fn select(&mut self, tab: &str) -> Result<(), &'static str> {
        self.tab = match tab {
            "profile" => "profile",
            "ops" => "ops",
            _ => STACKS.into_iter().find(|t| *t == tab).ok_or(INVALID)?,
        };
        self.compose = None;
        self.snooze = false;
        self.changed();
        Ok(())
    }

    fn stack(&mut self, tab: &str) -> &mut Option<String> {
        match tab {
            "lounges" => &mut self.lounge_id,
            "dms" => &mut self.dm_id,
            _ => &mut self.thread_id,
        }
    }

    /// Another account's conversations aren't this one's: closes them and
    /// Start conversation, but stays on the selected tab.
    pub fn reset(&mut self) {
        let (tab, revision) = (self.tab, self.revision);
        *self = Self {
            tab,
            revision,
            ..Self::default()
        };
        self.changed();
    }

    fn changed(&mut self) {
        let tab = self.tab;
        self.path = match tab {
            "profile" => "/profile".into(),
            "ops" => "/ops".into(),
            _ if self.compose.is_some() => Destination::NewThread {
                dictate: self.compose == Some("dictation"),
            }
            .path(),
            "threads" if self.snooze && self.thread_id.is_some() => {
                Destination::Snooze(self.thread_id.clone().unwrap_or_default()).path()
            }
            _ => match self.stack(tab) {
                Some(id) => format!("/{tab}/{id}"),
                None => format!("/{tab}"),
            },
        };
        self.revision += 1;
    }
}
