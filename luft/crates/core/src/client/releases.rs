//! Online-only, immutable release review. No release mutation enters the outbox.
use super::*;

const INVALID: &str = "Invalid release response";
const CHANGED: &str = "The release session changed. Open it again.";

#[derive(Default)]
pub struct ReleaseReviews {
    context: Option<(u64, String)>,
    authority: Option<(String, String, String)>,
    list: Value,
    detail: Value,
}

pub(super) type Releases = ReleaseReviews;

impl MobileClient {
    pub(super) fn release_operation(
        &mut self,
        op: &str,
        args: &Value,
        host: &mut dyn Host,
    ) -> Result<Value> {
        if op == "release_close" {
            if self
                .releases
                .context
                .as_ref()
                .is_some_and(|(generation, surface)| {
                    args["generation"].as_u64() == Some(*generation)
                        && args["surface"] == surface.as_str()
                })
            {
                self.releases = Default::default();
            }
            return Ok(json!({"surface":{"list":null,"detail":null},"error":null}));
        }
        let generation = self.vault.generation;
        let binding = (|| {
            let index = self.active()?;
            let surface = text(args, "surface")?;
            if args["generation"].as_u64() != Some(generation) || !is_uuid(surface) {
                return Err(CHANGED);
            }
            Ok((
                index,
                surface,
                server_url(&self.vault.profiles[index].server)?,
            ))
        })();
        let (index, surface, server) = match binding {
            Ok(binding) => binding,
            Err(error) => {
                self.releases = Default::default();
                return Ok(json!({"surface":{"list":null,"detail":null},"error":error}));
            }
        };
        let account = self.account(index).to_owned();
        let identity = self.vault.profiles[index].identity.clone();
        let profiles = self.vault.profiles.clone();
        let mut state = std::mem::take(&mut self.releases);
        let response = state.call(
            &server,
            &account,
            &identity,
            generation,
            surface,
            op,
            args,
            &mut Authorized {
                client: self,
                index,
                host,
            },
            |detail| {
                let mut safe = detail.clone();
                scrub(&mut safe, &profiles);
                safe == *detail
            },
        );
        if generation != self.vault.generation {
            self.releases = Default::default();
            return Ok(json!({"surface":{"list":null,"detail":null},"error":CHANGED}));
        }
        self.releases = state;
        response
    }
}

impl ReleaseReviews {
    /// Online-only review authority. The caller must discard this owner when its
    /// session or visible surface changes. Mutations are never retried.
    ///
    /// Runs `releases`, `release_open`, `release_approve`, `release_merge`, or `release_activate`;
    /// detail operations require `args.hash`. Returns the mobile-compatible
    /// `{surface: {list, detail}, error}` envelope. Identity is the authenticated
    /// user's `user:<id>`, not the organization ID. Generation and surface bind
    /// the visible review; transport must independently reject expired sessions.
    /// `exact` rejects a definition the host would redact or otherwise change;
    /// a desktop transport that preserves JSON can pass `|_| true`.
    #[allow(clippy::too_many_arguments)]
    pub fn call(
        &mut self,
        server: &Url,
        account: &str,
        identity: &str,
        generation: u64,
        surface: &str,
        op: &str,
        args: &Value,
        transport: &mut dyn Transport,
        exact: impl Fn(&Value) -> bool,
    ) -> Result<Value> {
        let mut state = std::mem::take(self);
        let result = (|| {
            let context = (generation, surface.to_owned());
            let authority = (server.to_string(), account.to_owned(), identity.to_owned());
            if !segment(account) {
                return Err("Invalid account");
            }
            let base = endpoint(server, &format!("api/accounts/{account}/releases"));
            if op == "releases" {
                state = Releases {
                    context: Some(context),
                    authority: Some(authority),
                    ..Default::default()
                };
                state.list = Self::release_list(&base, transport)?;
            } else {
                let hash = text(args, "hash")?;
                if !release_hash(hash) {
                    return Err("Invalid release hash");
                }
                if op != "release_open" {
                    if state.context.as_ref() != Some(&context)
                        || state.authority.as_ref() != Some(&authority)
                        || state.detail["hash"] != hash
                    {
                        return Err(CHANGED);
                    }
                    let capability = match op {
                        "release_approve" => "approve",
                        "release_merge" => "merge",
                        "release_activate" => "activate",
                        _ => return Err("Unknown release operation"),
                    };
                    if !state.detail["actions"]
                        .as_array()
                        .is_some_and(|a| a.contains(&json!(capability)))
                    {
                        return Err("This release action is unavailable.");
                    }
                    // Consume authority before sending. An uncertain outcome requires a fresh review.
                    state.detail = Value::Null;
                    let value = Self::release_http(
                        "POST",
                        release_url(&base, &format!("/{hash}/{capability}"))?,
                        Some(json!({})),
                        transport,
                    )?;
                    if value["hash"] != hash {
                        return Err(INVALID);
                    }
                    state.list = Self::release_list(&base, transport)?;
                }
                state.detail = Value::Null;
                let mut detail = Self::release_http(
                    "GET",
                    release_url(&base, &format!("/{hash}"))?,
                    None,
                    transport,
                )?;
                if !exact(&detail) {
                    return Err("This release cannot be displayed exactly with this session.");
                }
                validate_metadata(&detail)?;
                if detail["hash"] != hash
                    || !detail["definition"].is_object()
                    || !(detail["baseline_definition"].is_object()
                        || detail.get("baseline_definition") == Some(&Value::Null))
                {
                    return Err(INVALID);
                }
                let changes = detail["changes"]
                    .as_array()
                    .filter(|c| c.len() <= 10_000)
                    .ok_or(INVALID)?;
                let mut rendered = Vec::new();
                let mut paths = HashSet::new();
                for change in changes {
                    let path = text_allow_empty(change, "path")?;
                    if !valid_pointer(path)
                        || !paths.insert(path)
                        || change.get("before").is_none()
                        || change.get("after").is_none()
                    {
                        return Err(INVALID);
                    }
                    let before = detail["baseline_definition"].pointer(path);
                    let after = detail["definition"].pointer(path);
                    let valid = match change["kind"].as_str() {
                        Some("added") => {
                            (before.is_none()
                                || (path.is_empty() && detail["baseline_definition"].is_null()))
                                && after == Some(&change["after"])
                                && change["before"].is_null()
                        }
                        Some("removed") => {
                            after.is_none()
                                && before == Some(&change["before"])
                                && change["after"].is_null()
                        }
                        Some("changed") => {
                            before == Some(&change["before"])
                                && after == Some(&change["after"])
                                && before != after
                        }
                        _ => false,
                    };
                    if !valid {
                        return Err(INVALID);
                    }
                    rendered.push(json!({"path":path,"kind":change["kind"],"before":pretty(&change["before"]),"after":pretty(&change["after"])}));
                }
                if !changes_cover(
                    Some(&detail["baseline_definition"]),
                    Some(&detail["definition"]),
                    "",
                    &paths,
                ) {
                    return Err(INVALID);
                }
                let mut actions = Vec::new();
                let author_is_self = detail["author"]
                    .as_i64()
                    .is_some_and(|id| identity == format!("user:{id}"));
                if detail["can_approve"] == true && detail["state"] == "proposed" && !author_is_self
                {
                    actions.push("approve");
                }
                if detail["can_merge"] == true
                    && matches!(detail["state"].as_str(), Some("approved" | "merging"))
                    && detail["merge_blockers"]
                        .as_array()
                        .is_some_and(Vec::is_empty)
                {
                    actions.push("merge");
                }
                if detail["can_activate"] == true
                    && detail["state"] == "merged"
                    && detail["compatible"] == true
                    && detail["active_at"].is_null()
                    && detail["blockers"].as_array().is_some_and(Vec::is_empty)
                {
                    actions.push("activate");
                }
                detail["actions"] = json!(actions);
                detail["review_changes"] = json!(rendered);
                detail["definition_text"] = json!(pretty(&detail["definition"]));
                detail["baseline_text"] = json!(pretty(&detail["baseline_definition"]));
                state.detail = detail;
                state.context = Some(context);
                state.authority = Some(authority);
            }
            Ok(())
        })();
        if result.is_err() {
            state = Default::default();
        }
        let response =
            json!({"surface":{"list":state.list,"detail":state.detail},"error":result.err()});
        *self = state;
        Ok(response)
    }

    fn release_list(base: &Url, transport: &mut dyn Transport) -> Result<Value> {
        let value = Self::release_http("GET", base.clone(), None, transport)?;
        if !(value.get("active") == Some(&Value::Null)
            || value["active"].as_str().is_some_and(release_hash))
        {
            return Err(INVALID);
        }
        let rows = value["releases"]
            .as_array()
            .filter(|r| r.len() <= 1000)
            .ok_or(INVALID)?;
        let mut hashes = HashSet::new();
        for row in rows {
            validate_metadata(row)?;
            if !hashes.insert(text(row, "hash")?) {
                return Err(INVALID);
            }
        }
        Ok(value)
    }

    fn release_http(
        method: &str,
        url: Url,
        body: Option<Value>,
        transport: &mut dyn Transport,
    ) -> Result<Value> {
        let (status, value) = transport.send(method, url, body)?;
        match status {
            200 => Ok(value),
            401 | 403 => Err("Releases unavailable with this session."),
            409 => Err("This release changed. Open it again before continuing."),
            _ => Err("Release request failed. Open it again to check its current state."),
        }
    }
}

fn release_url(base: &Url, suffix: &str) -> Result<Url> {
    Url::parse(&format!("{}{suffix}", base.as_str())).map_err(|_| INVALID)
}
fn release_hash(hash: &str) -> bool {
    segment(hash) && hash.len() <= 200
}
fn text_allow_empty<'a>(value: &'a Value, key: &str) -> Result<&'a str> {
    value[key]
        .as_str()
        .filter(|s| s.len() <= 16_000)
        .ok_or(INVALID)
}
fn valid_pointer(path: &str) -> bool {
    (path.is_empty() || path.starts_with('/'))
        && !path
            .as_bytes()
            .windows(2)
            .any(|w| w[0] == b'~' && !matches!(w[1], b'0' | b'1'))
        && !path.ends_with('~')
}
fn pretty(value: &Value) -> String {
    serde_json::to_string_pretty(value).unwrap()
}
// Every differing subtree must be represented, not just the changes the server chose to list.
fn changes_cover(
    before: Option<&Value>,
    after: Option<&Value>,
    path: &str,
    paths: &HashSet<&str>,
) -> bool {
    if before == after || paths.contains(path) {
        return true;
    }
    let left = before.and_then(Value::as_object);
    let right = after.and_then(Value::as_object);
    if left.is_some() || right.is_some() {
        let keys: HashSet<_> = left
            .into_iter()
            .flat_map(|o| o.keys())
            .chain(right.into_iter().flat_map(|o| o.keys()))
            .collect();
        return !keys.is_empty()
            && keys.into_iter().all(|key| {
                changes_cover(
                    left.and_then(|o| o.get(key)),
                    right.and_then(|o| o.get(key)),
                    &format!("{path}/{}", key.replace('~', "~0").replace('/', "~1")),
                    paths,
                )
            });
    }
    if let (Some(left), Some(right)) = (
        before.and_then(Value::as_array),
        after.and_then(Value::as_array),
    ) {
        return (0..left.len().max(right.len()))
            .all(|i| changes_cover(left.get(i), right.get(i), &format!("{path}/{i}"), paths));
    }
    false
}
fn validate_metadata(value: &Value) -> Result<()> {
    if !value["hash"].as_str().is_some_and(release_hash)
        || !(value.get("baseline") == Some(&Value::Null)
            || value["baseline"].as_str().is_some_and(release_hash))
        || text(value, "title")?.len() > 1000
        || value["author"].as_i64().is_none()
        || !(value.get("reviewer") == Some(&Value::Null) || value["reviewer"].as_i64().is_some())
        || !matches!(
            value["state"].as_str(),
            Some(
                "proposed"
                    | "approved"
                    | "merging"
                    | "merged"
                    | "merge_conflict"
                    | "active"
                    | "superseded"
                    | "stale"
            )
        )
        || value.get("can_merge").is_some_and(|v| !v.is_boolean())
        || value.get("merge_blockers").is_some_and(|v| {
            !v.as_array().is_some_and(|b| {
                b.len() <= 100
                    && b.iter()
                        .all(|s| s.as_str().is_some_and(|s| !s.is_empty() && s.len() <= 4000))
            })
        })
        || ["compatible", "can_approve", "can_activate"]
            .iter()
            .any(|k| !value[k].is_boolean())
        || !value["blockers"].as_array().is_some_and(|b| {
            b.len() <= 100
                && b.iter()
                    .all(|s| s.as_str().is_some_and(|s| !s.is_empty() && s.len() <= 4000))
        })
        || !value["created_at"].as_str().is_some_and(iso_time)
        || !(value.get("active_at") == Some(&Value::Null)
            || value["active_at"].as_str().is_some_and(iso_time))
    {
        return Err(INVALID);
    }
    Ok(())
}
fn iso_time(value: &str) -> bool {
    // Validate calendar/time fields and an explicit RFC3339 zone; never infer device time.
    let b = value.as_bytes();
    if b.len() < 20
        || b.len() > 40
        || !value.is_ascii()
        || b[4] != b'-'
        || b[7] != b'-'
        || b[10] != b'T'
        || b[13] != b':'
        || b[16] != b':'
    {
        return false;
    }
    let number = |a: usize, z: usize| -> Option<u32> {
        let part = &value[a..z];
        if part.bytes().all(|b| b.is_ascii_digit()) {
            part.parse().ok()
        } else {
            None
        }
    };
    let Some(year) = number(0, 4) else {
        return false;
    };
    let Some(month) = number(5, 7) else {
        return false;
    };
    let days = match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) => 29,
        2 => 28,
        _ => return false,
    };
    if !number(8, 10).is_some_and(|n| (1..=days).contains(&n))
        || !number(11, 13).is_some_and(|n| n <= 23)
        || !number(14, 16).is_some_and(|n| n <= 59)
        || !number(17, 19).is_some_and(|n| n <= 59)
    {
        return false;
    }
    let zone = if b.last() == Some(&b'Z') {
        b.len() - 1
    } else {
        let z = b.len() - 6;
        if z < 19
            || !matches!(b[z], b'+' | b'-')
            || b[z + 3] != b':'
            || !number(z + 1, z + 3).is_some_and(|n| n <= 23)
            || !number(z + 4, z + 6).is_some_and(|n| n <= 59)
        {
            return false;
        }
        z
    };
    zone == 19 || (zone > 20 && b[19] == b'.' && b[20..zone].iter().all(u8::is_ascii_digit))
}
