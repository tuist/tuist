//! Lounges and direct conversations: long-lived conversations between people in
//! an organization, with no agent. Every member reads a lounge; a direct
//! conversation belongs to the people in it. Neither ends, so instead of a
//! state each one has an unread count from the person's read position.
use serde_json::{Value, json};
use tuist_oauth::endpoint;
use url::Url;

use crate::client::{NOT_FOUND, Result, segment, successful, text};
use crate::threads::{Transport, new_request_id};

const NAME_TAKEN: &str = "A lounge with this name already exists";

/// One person's lounge operations. Like `Threads`, it keeps the idempotency
/// key of a write that has not succeeded yet, so retrying the same text never
/// posts it twice.
#[derive(Default)]
pub struct Lounges {
    pending: Option<(String, String)>,
}

impl Lounges {
    pub fn new() -> Self {
        Self::default()
    }

    /// Runs `lounges`, `lounge`, `send_lounge_message`, `read_lounge`, `create_lounge`,
    /// `start_direct` or `lounge_people` (see the crate README) in the account
    /// `handle` on `server`. Lounges belong to organizations: for a personal
    /// account (`organization` false) `lounges` answers `available: false`
    /// without a request.
    pub fn call(
        &mut self,
        server: &Url,
        handle: &str,
        organization: bool,
        operation: &str,
        args: &Value,
        transport: &mut dyn Transport,
    ) -> Result<Value> {
        if !segment(handle) {
            return Err("Invalid account");
        }
        let url = |path: &str| {
            endpoint(
                server,
                format!("api/accounts/{handle}/lounges/{path}").trim_end_matches('/'),
            )
        };
        let unavailable =
            |reason| json!({"available":false,"reason":reason,"lounges":[],"directs":[]});
        if !organization {
            return match operation {
                "lounges" => Ok(unavailable("personal")),
                _ => Err("Lounges belong to organizations; switch to one to use them"),
            };
        }
        let mut request = |method, url, body| successful(transport.send(method, url, body)?);
        match operation {
            "lounges" => {
                let mut data = match request("GET", url(""), None) {
                    // The server answers missing flags and membership with 404.
                    Err(NOT_FOUND) => return Ok(unavailable("disabled")),
                    Err("Access denied") => return Ok(unavailable("sign_in_required")),
                    result => result?,
                };
                data["available"] = json!(true);
                for key in ["lounges", "directs"] {
                    for lounge in data[key].as_array_mut().ok_or("Invalid lounges")? {
                        present(lounge);
                    }
                }
                Ok(data)
            }
            "lounge" => {
                let mut url = url(id(args)?);
                if let Some(before) = args.get("before").and_then(Value::as_u64) {
                    url.query_pairs_mut()
                        .append_pair("before", &before.to_string());
                }
                let mut lounge = request("GET", url, None)?;
                present(&mut lounge);
                Ok(lounge)
            }
            "send_lounge_message" => {
                let id = id(args)?;
                let content = text(args, "content")?;
                if content.trim().is_empty() {
                    return Err("Write a message first");
                }
                if content.len() > 16_000 {
                    return Err("Message is too long");
                }
                let body = json!({
                    "request_id": self.request_id(&format!("{server}\n{handle}\n{id}\n{content}")),
                    "content": content,
                });
                let mut lounge = request("POST", url(&format!("{id}/messages")), Some(body))?;
                self.pending = None;
                present(&mut lounge);
                Ok(lounge)
            }
            "read_lounge" => {
                let position = args
                    .get("position")
                    .and_then(Value::as_u64)
                    .filter(|p| *p > 0)
                    .ok_or("Invalid position")?;
                request(
                    "POST",
                    url(&format!("{}/read", id(args)?)),
                    Some(json!({"position": position})),
                )
            }
            "create_lounge" => {
                let name = normalized_name(text(args, "name")?)?;
                let topic = args
                    .get("topic")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .trim();
                if topic.chars().count() > 250 {
                    return Err("The topic is too long");
                }
                let invited = user_ids(args, 50)?;
                let body = json!({
                    "request_id": self.request_id(&format!("{server}\n{handle}\n#{name}")),
                    "name": name,
                    "topic": topic,
                    "user_ids": invited,
                });
                let mut lounge = match transport.send("POST", url(""), Some(body))? {
                    // Other conflicts (a reused request) stay generic errors.
                    (409, body) if body["code"] == "name_taken" => return Err(NAME_TAKEN),
                    response => successful(response)?,
                };
                self.pending = None;
                present(&mut lounge);
                Ok(lounge)
            }
            "start_direct" => {
                let mut ids: Vec<u64> = args
                    .get("user_ids")
                    .and_then(Value::as_array)
                    .ok_or("Choose who to message")?
                    .iter()
                    .map(|v| v.as_u64().ok_or("Invalid person"))
                    .collect::<Result<_>>()?;
                ids.sort_unstable();
                ids.dedup();
                if ids.is_empty() || ids.len() > 7 {
                    return Err("Choose one to seven people");
                }
                let key = format!("{server}\n{handle}\n{ids:?}");
                let body = json!({"request_id": self.request_id(&key), "user_ids": ids});
                let mut lounge = request("POST", url("directs"), Some(body))?;
                self.pending = None;
                present(&mut lounge);
                Ok(lounge)
            }
            "invite_lounge" => {
                let ids = user_ids(args, 50)?;
                if ids.is_empty() {
                    return Err("Choose who to invite");
                }
                let mut lounge = request(
                    "POST",
                    url(&format!("{}/members", id(args)?)),
                    Some(json!({"user_ids": ids})),
                )?;
                present(&mut lounge);
                Ok(lounge)
            }
            "lounge_people" => request("GET", url("people"), None),
            _ => Err("Unknown operation"),
        }
    }

    fn request_id(&mut self, key: &str) -> String {
        match &self.pending {
            Some((pending, id)) if pending == key => id.clone(),
            _ => {
                let id = new_request_id();
                self.pending = Some((key.to_string(), id.clone()));
                id
            }
        }
    }
}

/// The organizations the signed-in person belongs to on `server`, for
/// frontends without the mobile client's account menu (GPUI). Lounges default to
/// the first; an empty list means only the personal account, which has none.
pub fn organizations(server: &Url, transport: &mut dyn Transport) -> Result<Vec<String>> {
    let data = successful(transport.send("GET", endpoint(server, "api/organizations"), None)?)?;
    data["organizations"]
        .as_array()
        .ok_or("Invalid organizations")?
        .iter()
        .map(|o| {
            let name = text(o, "name")?;
            if segment(name) {
                Ok(name.to_string())
            } else {
                Err("Invalid organizations")
            }
        })
        .collect()
}

/// Adds what every frontend shows the same way: `title` (`#name` for a lounge,
/// the other people's handles for a direct conversation).
fn present(lounge: &mut Value) {
    let title = match lounge["kind"].as_str() {
        Some("lounge") => format!("#{}", lounge["name"].as_str().unwrap_or_default()),
        _ => {
            let names: Vec<&str> = lounge["members"]
                .as_array()
                .map(|m| m.iter().filter_map(|p| p["handle"].as_str()).collect())
                .unwrap_or_default();
            names.join(", ")
        }
    };
    lounge["title"] = json!(title);
}

/// The optional `user_ids` people to invite: at most `limit`, without repeats.
fn user_ids(args: &Value, limit: usize) -> Result<Vec<u64>> {
    let Some(ids) = args.get("user_ids").filter(|v| !v.is_null()) else {
        return Ok(vec![]);
    };
    let mut ids: Vec<u64> = ids
        .as_array()
        .ok_or("Invalid person")?
        .iter()
        .map(|v| v.as_u64().ok_or("Invalid person"))
        .collect::<Result<_>>()?;
    ids.sort_unstable();
    ids.dedup();
    if ids.len() > limit {
        return Err("Invite at most 50 people at once");
    }
    Ok(ids)
}

fn id(args: &Value) -> Result<&str> {
    let id = text(args, "id")?;
    if id.len() == 36 && id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
        Ok(id)
    } else {
        Err("Invalid lounge")
    }
}

/// The server's lounge name rules, checked before the request so a typo gets a
/// helpful message: lowercase letters, digits, `-` and `_`, spaces become
/// `-`, and a leading `#` is dropped.
fn normalized_name(value: &str) -> Result<String> {
    let name = value
        .trim()
        .trim_start_matches('#')
        .trim()
        .to_lowercase()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join("-");
    let valid = !name.is_empty()
        && name.len() <= 64
        && name
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-' || b == b'_')
        && !name.starts_with(['-', '_']);
    if valid {
        Ok(name)
    } else {
        Err("Use letters, numbers, - or _ for the lounge name")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Recorder {
        requests: Vec<(String, String, Option<Value>)>,
        responses: Vec<(u64, Value)>,
    }

    impl Transport for Recorder {
        fn send(&mut self, method: &str, url: Url, body: Option<Value>) -> Result<(u64, Value)> {
            self.requests.push((method.into(), url.to_string(), body));
            Ok(self.responses.remove(0))
        }
    }

    fn recorder(responses: Vec<(u64, Value)>) -> Recorder {
        Recorder {
            requests: vec![],
            responses,
        }
    }

    fn server() -> Url {
        Url::parse("https://tuist.dev").unwrap()
    }

    const ID: &str = "0b7e3a52-2f4c-4f63-9a8e-6f0b7f8d1c2a";

    #[test]
    fn organizations_lists_names_and_rejects_unsafe_ones() {
        let mut transport = recorder(vec![
            (
                200,
                json!({"organizations":[{"name":"tuist"},{"name":"acme"}]}),
            ),
            (200, json!({"organizations":[{"name":"../evil"}]})),
        ]);
        assert_eq!(
            organizations(&server(), &mut transport).unwrap(),
            ["tuist", "acme"]
        );
        assert_eq!(
            transport.requests[0].1,
            "https://tuist.dev/api/organizations"
        );
        assert!(organizations(&server(), &mut transport).is_err());
    }

    #[test]
    fn personal_accounts_have_no_lounges_and_send_nothing() {
        let mut transport = recorder(vec![]);
        let data = Lounges::new()
            .call(
                &server(),
                "ana",
                false,
                "lounges",
                &json!({}),
                &mut transport,
            )
            .unwrap();
        assert_eq!(data["available"], false);
        assert_eq!(data["reason"], "personal");
        assert!(
            Lounges::new()
                .call(
                    &server(),
                    "ana",
                    false,
                    "lounge",
                    &json!({"id":ID}),
                    &mut transport
                )
                .is_err()
        );
        assert!(transport.requests.is_empty());
    }

    #[test]
    fn titles_name_lounges_and_the_other_people_in_a_direct_conversation() {
        let mut transport = recorder(vec![
            (
                200,
                json!({"lounges":[{"kind":"lounge","name":"releases"}],
                       "directs":[{"kind":"direct","members":[{"id":2,"handle":"ben"},{"id":3,"handle":"cai"}]}]}),
            ),
            (404, json!({})),
            (401, json!({})),
        ]);
        let mut lounges = Lounges::new();
        let data = lounges
            .call(
                &server(),
                "tuist",
                true,
                "lounges",
                &json!({}),
                &mut transport,
            )
            .unwrap();
        assert_eq!(data["available"], true);
        assert_eq!(data["lounges"][0]["title"], "#releases");
        assert_eq!(data["directs"][0]["title"], "ben, cai");
        assert_eq!(
            transport.requests[0].1,
            "https://tuist.dev/api/accounts/tuist/lounges"
        );
        let disabled = lounges
            .call(
                &server(),
                "tuist",
                true,
                "lounges",
                &json!({}),
                &mut transport,
            )
            .unwrap();
        assert_eq!(disabled["reason"], "disabled");
        let refused = lounges
            .call(
                &server(),
                "tuist",
                true,
                "lounges",
                &json!({}),
                &mut transport,
            )
            .unwrap();
        assert_eq!(refused["reason"], "sign_in_required");
    }

    #[test]
    fn a_failed_send_retries_under_the_same_request_id_and_a_new_message_gets_a_new_one() {
        let mut transport = recorder(vec![
            (500, json!({})),
            (200, json!({"kind":"lounge","name":"general","messages":[]})),
            (200, json!({"kind":"lounge","name":"general","messages":[]})),
        ]);
        let mut lounges = Lounges::new();
        let args = json!({"id":ID,"content":"Morning"});
        assert!(
            lounges
                .call(
                    &server(),
                    "tuist",
                    true,
                    "send_lounge_message",
                    &args,
                    &mut transport
                )
                .is_err()
        );
        lounges
            .call(
                &server(),
                "tuist",
                true,
                "send_lounge_message",
                &args,
                &mut transport,
            )
            .unwrap();
        lounges
            .call(
                &server(),
                "tuist",
                true,
                "send_lounge_message",
                &args,
                &mut transport,
            )
            .unwrap();
        let ids: Vec<&Value> = transport
            .requests
            .iter()
            .map(|r| &r.2.as_ref().unwrap()["request_id"])
            .collect();
        assert_eq!(ids[0], ids[1]);
        assert_ne!(ids[1], ids[2]);
        assert_eq!(
            transport.requests[0].1,
            format!("https://tuist.dev/api/accounts/tuist/lounges/{ID}/messages")
        );
    }

    #[test]
    fn lounge_names_follow_the_server_rules_and_taken_names_say_so() {
        assert_eq!(
            normalized_name(" # Release  Talk ").unwrap(),
            "release-talk"
        );
        assert!(normalized_name("no/slashes").is_err());
        assert!(normalized_name("#").is_err());
        assert!(normalized_name("-leading").is_err());
        let mut transport = recorder(vec![(409, json!({"code":"name_taken"}))]);
        let error = Lounges::new()
            .call(
                &server(),
                "tuist",
                true,
                "create_lounge",
                &json!({"name":"General"}),
                &mut transport,
            )
            .unwrap_err();
        assert_eq!(error, NAME_TAKEN);
        assert_eq!(transport.requests[0].2.as_ref().unwrap()["name"], "general");
    }

    #[test]
    fn invites_post_the_people_to_the_lounges_members() {
        let mut transport = recorder(vec![
            (
                200,
                json!({"kind":"lounge","name":"design","member_ids":[3]}),
            ),
            (
                200,
                json!({"kind":"lounge","name":"design","member_ids":[2]}),
            ),
        ]);
        let mut lounges = Lounges::new();
        let lounge = lounges
            .call(
                &server(),
                "tuist",
                true,
                "invite_lounge",
                &json!({"id":ID,"user_ids":[3,3]}),
                &mut transport,
            )
            .unwrap();
        assert_eq!(lounge["title"], "#design");
        assert_eq!(
            transport.requests[0].1,
            format!("https://tuist.dev/api/accounts/tuist/lounges/{ID}/members")
        );
        assert_eq!(
            transport.requests[0].2.as_ref().unwrap()["user_ids"],
            json!([3])
        );
        assert!(
            lounges
                .call(
                    &server(),
                    "tuist",
                    true,
                    "invite_lounge",
                    &json!({"id":ID,"user_ids":[]}),
                    &mut transport
                )
                .is_err()
        );
        lounges
            .call(
                &server(),
                "tuist",
                true,
                "create_lounge",
                &json!({"name":"design","user_ids":[2]}),
                &mut transport,
            )
            .unwrap();
        assert_eq!(
            transport.requests[1].2.as_ref().unwrap()["user_ids"],
            json!([2])
        );
    }

    #[test]
    fn direct_conversations_need_one_to_seven_other_people() {
        let mut transport = recorder(vec![(
            200,
            json!({"kind":"direct","members":[{"id":3,"handle":"cai"}]}),
        )]);
        let mut lounges = Lounges::new();
        for ids in [json!([]), json!([1, 2, 3, 4, 5, 6, 7, 8]), json!(["1"])] {
            assert!(
                lounges
                    .call(
                        &server(),
                        "tuist",
                        true,
                        "start_direct",
                        &json!({"user_ids":ids}),
                        &mut transport
                    )
                    .is_err()
            );
        }
        let direct = lounges
            .call(
                &server(),
                "tuist",
                true,
                "start_direct",
                &json!({"user_ids":[3,3]}),
                &mut transport,
            )
            .unwrap();
        assert_eq!(direct["title"], "cai");
        assert_eq!(
            transport.requests[0].2.as_ref().unwrap()["user_ids"],
            json!([3])
        );
    }
}
