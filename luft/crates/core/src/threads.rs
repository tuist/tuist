//! Threads: conversations that run on the server. Each frontend lists them,
//! starts them and replies through these operations; the person never picks a
//! repository, machine or model.
use base64::{Engine, engine::general_purpose::STANDARD};
use serde_json::{Value, json};
use tuist_oauth::{Pkce, endpoint};
use url::Url;

use crate::client::{NOT_FOUND, Result, segment, successful, text};

/// The server refuses a thread on a runner that hasn't polled in the last
/// minute, rather than leaving every tool call to time out.
const RUNNER_OFFLINE: &str =
    "That runner is offline. Open Luft on that machine and check its runner is connected";

const NOT_WORKING: &str = "This thread already finished, so there's nothing to wait for";

// The server answers 404 when threads are off for the user (the `code` flag)
// or it predates them.
pub const THREADS_UNAVAILABLE: &str = "Threads aren't enabled for this account or server";

/// Sends authorized requests for the signed-in person. The mobile client
/// implements it with its vault and native host; GPUI with its desktop session.
pub trait Transport {
    /// Sends `body` as JSON with the session's bearer token, and returns the
    /// response status and its parsed JSON body (null when empty or invalid).
    fn send(&mut self, method: &str, url: Url, body: Option<Value>) -> Result<(u64, Value)>;
}

/// One person's thread operations. Keep one per process or session: it holds
/// the idempotency key of a request that has not succeeded yet, so that
/// retrying the same text never posts it twice.
#[derive(Default)]
pub struct Threads {
    pending: Option<(String, String)>,
}

impl Threads {
    pub fn new() -> Self {
        Self::default()
    }

    /// Runs `threads`, `start_thread`, `thread`, `send_message`, `answer_question`,
    /// `snooze_thread` or `archive_thread` (see the crate README) in the account `handle` on `server`: the person's own
    /// account or a selected organization. The server lists only the threads
    /// the user owns there, and requires admin rights and the organization's
    /// `luft` flag on an organization.
    pub fn call(
        &mut self,
        server: &Url,
        handle: &str,
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
                format!("api/accounts/{handle}/threads/{path}").trim_end_matches('/'),
            )
        };
        let request = |transport: &mut dyn Transport, method, url, body| {
            successful(transport.send(method, url, body)?)
        };
        match operation {
            "threads" => {
                let mut url = url("");
                let cursor = args.get("cursor").and_then(Value::as_str);
                if let Some(cursor) = cursor {
                    if cursor.is_empty() {
                        return Err("Invalid cursor");
                    }
                    url.query_pairs_mut().append_pair("cursor", cursor);
                }
                let unavailable = |reason| json!({"available":false,"reason":reason,"threads":[],"next_cursor":null});
                let mut data = match request(transport, "GET", url, None) {
                    Err(NOT_FOUND) => return Ok(unavailable("disabled")),
                    // The server answers missing rights and flags with 404, so a
                    // refusal means this session predates Luft's first-party
                    // client. Signing in again uses it.
                    Err("Access denied") => return Ok(unavailable("sign_in_required")),
                    result => result?,
                };
                data["available"] = json!(true);
                // A server repeating the cursor it was given would page forever.
                if cursor.is_some() && data["next_cursor"].as_str() == cursor {
                    data["next_cursor"] = Value::Null;
                }
                for thread in data["threads"].as_array_mut().ok_or("Invalid threads")? {
                    present(thread);
                }
                Ok(data)
            }
            "start_thread" => {
                let content = message_content(args)?;
                let catalog = match request(transport, "GET", url("models"), None) {
                    Err(NOT_FOUND) => return Err(THREADS_UNAVAILABLE),
                    result => result?,
                };
                let model = catalog["models"]
                    .as_array()
                    .and_then(|models| {
                        models.iter().find(|m| {
                            m["provider"].as_str().is_some_and(|v| !v.is_empty())
                                && m["id"].as_str().is_some_and(|v| !v.is_empty())
                        })
                    })
                    .ok_or("Connect a ChatGPT subscription in your Tuist account settings to start conversations")?;
                let runner = runner_id(args)?;
                let mut body = json!({
                    "request_id": self.request_id(args, server, handle, runner.unwrap_or(""), content)?,
                    "content": content,
                    "attachments": attachments(args)?,
                    "provider": model["provider"],
                    "model": model["id"],
                });
                if let Some(runner) = runner {
                    body["runner_id"] = json!(runner);
                }
                let mut thread = match transport.send("POST", url(""), Some(body))? {
                    (409, data) if data["reason"] == "runner_offline" => {
                        return Err(RUNNER_OFFLINE);
                    }
                    response => match successful(response) {
                        Err(NOT_FOUND) => return Err(THREADS_UNAVAILABLE),
                        result => result?,
                    },
                };
                self.pending = None;
                present(&mut thread);
                Ok(thread)
            }
            "thread" => {
                let mut url = url(thread_id(args)?);
                if let Some(before) = args.get("before").and_then(Value::as_u64) {
                    url.query_pairs_mut()
                        .append_pair("before", &before.to_string());
                }
                let mut thread = request(transport, "GET", url, None)?;
                present(&mut thread);
                Ok(thread)
            }
            "send_message" | "answer_question" => {
                let id = thread_id(args)?;
                let content = message_content(args)?;
                let mut body = json!({
                    "request_id": self.request_key(server, handle, operation, args)?,
                    "content": content,
                    "attachments": attachments(args)?,
                });
                if operation == "answer_question" {
                    let question = text(args, "question_id")?;
                    if question.len() != 36
                        || !question.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-')
                    {
                        return Err("Invalid question");
                    }
                    body["question_id"] = json!(question);
                    match (args.get("option_id"), args.get("cancel")) {
                        (None, Some(Value::Bool(true))) => body["cancel"] = json!(true),
                        (Some(Value::String(option)), None) if !option.is_empty() => {
                            body["option_id"] = json!(option);
                        }
                        _ => return Err("Choose an option or dismiss the question"),
                    }
                }
                let mut thread = request(
                    transport,
                    "POST",
                    url(&format!("{id}/messages")),
                    Some(body),
                )?;
                self.pending = None;
                present(&mut thread);
                Ok(thread)
            }
            "snooze_thread" => {
                let id = thread_id(args)?;
                let snooze = match args.get("snooze") {
                    None | Some(Value::Null) => Value::Null,
                    Some(Value::String(until)) if until == "until_needed" => {
                        json!({"until_needed": true})
                    }
                    Some(Value::String(until))
                        if parse_time(until).is_some_and(|until| until > now()) =>
                    {
                        json!({"until": until})
                    }
                    Some(_) => return Err("Invalid snooze"),
                };
                let mut thread =
                    match transport.send("PATCH", url(id), Some(json!({"snooze": snooze})))? {
                        // Only a working thread can wait until it's needed.
                        (409, _) if snooze["until_needed"] == true => return Err(NOT_WORKING),
                        response => successful(response)?,
                    };
                present(&mut thread);
                Ok(thread)
            }
            "reauthorize_thread" => {
                let id = thread_id(args)?;
                if args["consent"] != true {
                    return Err("Owner consent is required to authorize future messages");
                }
                let mut thread = request(
                    transport,
                    "POST",
                    url(&format!("{id}/reauthorize")),
                    Some(json!({})),
                )?;
                present(&mut thread);
                Ok(thread)
            }
            "archive_thread" => {
                let id = thread_id(args)?;
                // `archived: false` restores it.
                let status = match args.get("archived") {
                    None | Some(Value::Bool(true)) => "archived",
                    Some(Value::Bool(false)) => "active",
                    Some(_) => return Err("Invalid archived"),
                };
                let mut thread =
                    request(transport, "PATCH", url(id), Some(json!({"status": status})))?;
                present(&mut thread);
                Ok(thread)
            }
            _ => Err("Unknown operation"),
        }
    }

    /// The idempotency key `start_thread` or `send_message` will send with
    /// `args`, chosen before the request so a caller that queues the write
    /// after a lost response replays it under the same key.
    pub(crate) fn request_key(
        &mut self,
        server: &Url,
        handle: &str,
        operation: &str,
        args: &Value,
    ) -> Result<String> {
        let thread = match operation {
            "send_message" | "answer_question" => thread_id(args)?,
            // The same request on another runner is another thread.
            _ => runner_id(args)?.unwrap_or(""),
        };
        let content = message_content(args)?;
        if operation == "answer_question" {
            // The same label can answer different questions or options. Bind a
            // retry to the whole structured answer, not just its display text.
            let identity = json!([
                "answer_question",
                args["question_id"],
                args["option_id"],
                args["cancel"],
                content
            ]);
            self.request_id(args, server, handle, thread, &identity.to_string())
        } else {
            self.request_id(args, server, handle, thread, content)
        }
    }

    /// Forgets the in-memory key once its write is sent or queued, so the
    /// same text written again is a new message.
    pub(crate) fn settle(&mut self) {
        self.pending = None;
    }

    /// The caller's `request_id` when it gives one (the local store's outbox
    /// does, so a retry after a restart replays the same write), otherwise a
    /// key kept in memory until the request succeeds.
    fn request_id(
        &mut self,
        args: &Value,
        server: &Url,
        handle: &str,
        thread: &str,
        content: &str,
    ) -> Result<String> {
        if let Some(id) = args.get("request_id") {
            let id = id.as_str().ok_or("Invalid request")?;
            if id.len() != 36 || !id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
                return Err("Invalid request");
            }
            return Ok(id.to_string());
        }
        let files = attachments(args)?;
        let identity = if files.is_empty() {
            content.to_string()
        } else {
            serde_json::to_string(&json!([content, files])).map_err(|_| "Invalid attachments")?
        };
        Ok(self.memory_request_id(server, handle, thread, &identity))
    }

    fn memory_request_id(
        &mut self,
        server: &Url,
        handle: &str,
        thread: &str,
        content: &str,
    ) -> String {
        let key = format!("{server}\n{handle}\n{thread}\n{content}");
        match &self.pending {
            Some((pending, id)) if *pending == key => id.clone(),
            _ => {
                let id = new_request_id();
                self.pending = Some((key, id.clone()));
                id
            }
        }
    }
}

/// Adds what a thread means to the person: `state` from the server's agent
/// status, its inbox `section`, and whether it is still `working`, which
/// frontends use to keep an open conversation current.
fn present(thread: &mut Value) {
    // A run that ended (`idle`) is ready to review, and one that stopped
    // early (`interrupted`) needs attention like a failure.
    let state = match thread["status"].as_str() {
        Some("queued") => Some("queued"),
        Some("running" | "compacting" | "shipping") => Some("running"),
        Some("idle") => Some("completed"),
        Some("failed" | "interrupted") => Some("failed"),
        Some("outcome_unknown") => Some("outcome_unknown"),
        _ => None,
    };
    let archived = thread["archive_status"] == "archived";
    let working = matches!(state, Some("queued" | "running"));
    let section = if archived {
        "archived"
    } else if working {
        "in_progress"
    } else {
        "recent"
    };
    thread["state"] = json!(state);
    thread["section"] = json!(section);
    thread["working"] = json!(working && !archived);
    thread["can_reauthorize"] = json!(
        thread["can_reauthorize"] == true
            && thread["reauthorization_required"] == true
            && !working
            && !archived
            && state != Some("outcome_unknown")
    );
    present_snooze(thread, now());
    let mut activity = Value::Null;
    if let Some(messages) = thread["messages"].as_array_mut() {
        // The plan the run that's answering now shows: one after the person's
        // latest message.
        let current = messages
            .iter()
            .rposition(|m| m["role"] == "user" || m["progress"].is_object())
            .filter(|&i| working && !archived && messages[i]["role"] != "user");
        for (index, message) in messages.iter_mut().enumerate() {
            present_card(message);
            present_tool_result(message);
            present_build(message, working && !archived);
            let plan = present_progress(message, current == Some(index));
            if current == Some(index) {
                activity = plan;
            }
        }
    }
    thread["activity"] = activity;
    present_suggestions(thread);
}

/// Follow-ups belong only to the latest completed answer, never an earlier
/// turn or a reply queued offline. Edges put these in the composer, not on the wire.
fn present_suggestions(thread: &mut Value) {
    let latest = thread["messages"]
        .as_array()
        .and_then(|messages| messages.last());
    let suggestions = latest
        .filter(|message| {
            thread["state"] == "completed"
                && thread["archive_status"] != "archived"
                && message["role"] == "assistant"
        })
        .and_then(|message| message["suggestions"].as_array())
        .map(|values| {
            values
                .iter()
                .filter_map(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty() && value.chars().count() <= 120)
                .take(3)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let icons = suggestions
        .iter()
        .filter_map(|text| {
            let icon = latest?["suggestion_icons"][*text].as_str()?;
            matches!(icon, "investigate" | "test" | "explain" | "retry")
                .then(|| ((*text).to_owned(), json!(icon)))
        })
        .collect::<serde_json::Map<_, _>>();
    thread["suggestions"] = json!(suggestions);
    thread["suggestion_icons"] = json!(icons);
}

/// Whether the person snoozed the thread, which keeps it out of their way
/// until it matters again: `snooze` is `{until, until_needed}`, and the
/// thread's `section` is `snoozed`, while the server's `snoozed_until` is
/// still ahead or, with `snoozed_until_needed`, the thread still works.
/// Otherwise `snooze` is null. The core presents threads again when it reads
/// them from the store, so a snooze that ended offline ends on screen too.
pub(crate) fn present_snooze(thread: &mut Value, now: i64) {
    let until = thread["snoozed_until"].as_str().and_then(parse_time);
    let snoozed = thread["section"] != "archived"
        && (until.is_some_and(|until| until > now)
            || (thread["snoozed_until_needed"] == true
                && matches!(thread["state"].as_str(), Some("queued" | "running"))));
    if snoozed {
        thread["snooze"] = json!({
            "until": until.map(|_| thread["snoozed_until"].clone()),
            "until_needed": until.is_none(),
        });
        thread["section"] = json!("snoozed");
    } else if thread.get("snooze").is_some() {
        thread["snooze"] = Value::Null;
        if thread["section"] == "snoozed" {
            thread["section"] = json!(if thread["working"] == true {
                "in_progress"
            } else {
                "recent"
            });
        }
    }
}

/// Reconciles time-sensitive presentation after a thread came from the store.
/// Cached readiness is history, never evidence that the VM is ready now.
/// Suggestions also account for any queued messages overlaid by the store.
pub(crate) fn present_stored(view: &mut Value, now: i64) {
    match view.get_mut("threads").and_then(Value::as_array_mut) {
        Some(threads) => threads.iter_mut().for_each(|t| present_snooze(t, now)),
        None => {
            present_snooze(view, now);
            if view["freshness"]["state"] != "live" || view["working"] != true {
                view["workspace_ready_id"] = Value::Null;
            }
            present_suggestions(view);
        }
    }
}

/// When the person can snooze a thread until, from `now` (Unix seconds) at
/// a local time `offset_seconds` from UTC: `until_needed` while the thread
/// is `working`, in 1, 2 and 4 hours, this evening (18:00, before 17:00),
/// tomorrow and next Monday (09:00). Each option has its `id`, which the
/// edge labels, and the `until` time `snooze_thread` takes (null for
/// `until_needed`). A custom time is any later time the edge picks.
pub fn snooze_options(now: i64, offset_seconds: i64, working: bool) -> Value {
    const HOUR: i64 = 3600;
    const DAY: i64 = 24 * HOUR;
    let local = now + offset_seconds;
    let midnight = local.div_euclid(DAY) * DAY - offset_seconds;
    // 1970-01-01 was a Thursday, the fourth day of a week from Monday.
    let weekday = (local.div_euclid(DAY) + 3).rem_euclid(7);
    // On a Sunday, next Monday is tomorrow: the one after.
    let monday = if weekday == 6 { 8 } else { 7 - weekday };
    let mut options = Vec::new();
    if working {
        options.push(json!({"id": "until_needed", "until": null}));
    }
    for (id, hours) in [("in_1_hour", 1), ("in_2_hours", 2), ("in_4_hours", 4)] {
        options.push(json!({"id": id, "until": format_time(now + hours * HOUR)}));
    }
    if local - (midnight + offset_seconds) < 17 * HOUR {
        options.push(json!({"id": "this_evening", "until": format_time(midnight + 18 * HOUR)}));
    }
    options.push(json!({"id": "tomorrow", "until": format_time(midnight + DAY + 9 * HOUR)}));
    options
        .push(json!({"id": "next_week", "until": format_time(midnight + monday * DAY + 9 * HOUR)}));
    json!({"options": options})
}

fn now() -> i64 {
    web_time::SystemTime::now()
        .duration_since(web_time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64)
}

/// Unix seconds from a UTC RFC 3339 time such as `2026-11-18T18:00:00Z`, the
/// form the server writes, with optional fractional seconds.
fn parse_time(value: &str) -> Option<i64> {
    let value = value.strip_suffix('Z')?;
    let (date, time) = value.split_once('T')?;
    let time = time.split('.').next()?;
    let number = |s: &str, len: usize| {
        (s.len() == len && s.bytes().all(|b| b.is_ascii_digit())).then(|| s.parse::<i64>().ok())?
    };
    let mut date = date.split('-');
    let (y, m, d) = (
        number(date.next()?, 4)?,
        number(date.next()?, 2)?,
        number(date.next()?, 2)?,
    );
    let mut time = time.split(':');
    let (h, min, sec) = (
        number(time.next()?, 2)?,
        number(time.next()?, 2)?,
        number(time.next()?, 2)?,
    );
    if date.next().is_some()
        || time.next().is_some()
        || !(1..=12).contains(&m)
        || !(1..=31).contains(&d)
        || h > 23
        || min > 59
        || sec > 60
    {
        return None;
    }
    Some(days_from_civil(y, m, d) * 86_400 + h * 3600 + min * 60 + sec)
}

fn format_time(seconds: i64) -> String {
    let (days, time) = (seconds.div_euclid(86_400), seconds.rem_euclid(86_400));
    // Howard Hinnant's civil_from_days.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!(
        "{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}Z",
        time / 3600,
        time % 3600 / 60,
        time % 60
    )
}

/// Howard Hinnant's days_from_civil.
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y.rem_euclid(400);
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// Presentation is derived, never substituted for the original evidence.
fn present_tool_result(message: &mut Value) {
    if message["role"] != "tool" {
        return;
    }
    let raw = message["content"].as_str().unwrap_or_default();
    let formatted = serde_json::from_str::<Value>(raw)
        .ok()
        .and_then(|value| serde_json::to_string_pretty(&value).ok())
        .unwrap_or_else(|| raw.to_string());
    let readable = readable_tool_result(raw, 0);
    let preview: String = readable.chars().take(1200).collect();
    let decoded = serde_json::from_str::<Value>(&readable).unwrap_or(Value::Null);
    let cases = decoded["test_cases"]
        .as_array()
        .filter(|cases| !cases.is_empty() && cases.iter().all(|case| case["name"].is_string()))
        .map(|cases| {
            cases
                .iter()
                .map(|case| {
                    json!({
                        "name": case["name"], "module": case["module_name"].as_str(),
                        "suite": case["suite_name"].as_str(), "flaky": case["is_flaky"].as_bool(),
                        "state": case["state"].as_str(),
                    })
                })
                .collect::<Vec<_>>()
        });
    message["toolResult"] = json!({
        "text": readable,
        "preview": preview,
        "raw": formatted,
        "testCases": cases,
    });
}

fn readable_tool_result(text: &str, depth: usize) -> String {
    if depth == 4 {
        return text.to_string();
    }
    let Ok(value) = serde_json::from_str::<Value>(text) else {
        return text.to_string();
    };
    if let Some(inner) = value.as_str() {
        return readable_tool_result(inner, depth + 1);
    }
    // Only unwrap all-text MCP envelopes. Mixed image/resource results must
    // remain visible rather than silently losing their non-text evidence.
    if let Some(blocks) = value["content"].as_array().filter(|blocks| {
        !blocks.is_empty()
            && blocks
                .iter()
                .all(|block| block["type"] == "text" && block["text"].is_string())
    }) {
        return blocks
            .iter()
            .map(|block| readable_tool_result(block["text"].as_str().unwrap(), depth + 1))
            .collect::<Vec<_>>()
            .join("\n\n");
    }
    serde_json::to_string_pretty(&value).unwrap_or_else(|_| text.to_string())
}

/// A message's `progress` is the plan the agent shares with `update_progress`:
/// its `steps`, each a `title` and a `status` (`pending`, `in_progress` or
/// `completed`). The core counts the `completed` steps of the `total`, and
/// marks the plan `active` while the run that shows it still works, so edges
/// animate only a step that's really running. A plan this core can't show is
/// dropped, and the edge shows the message's `content`, the plan as a
/// checklist. Returns, for an active plan, what the thread is doing now: the
/// step in progress, or else the next one, with the counts.
fn present_progress(message: &mut Value, active: bool) -> Value {
    let Some(progress) = message.get_mut("progress") else {
        return Value::Null;
    };
    let steps = progress["steps"].as_array().filter(|steps| {
        !steps.is_empty()
            && steps.iter().all(|step| {
                step["title"].as_str().is_some_and(|t| !t.trim().is_empty())
                    && matches!(
                        step["status"].as_str(),
                        Some("pending" | "in_progress" | "completed")
                    )
            })
    });
    let Some(steps) = steps else {
        message.as_object_mut().map(|m| m.remove("progress"));
        return Value::Null;
    };
    let total = steps.len();
    let completed = steps.iter().filter(|s| s["status"] == "completed").count();
    let now = steps
        .iter()
        .find(|s| s["status"] == "in_progress")
        .or_else(|| steps.iter().find(|s| s["status"] == "pending"))
        .map(|s| s["title"].clone());
    progress["completed"] = json!(completed);
    progress["total"] = json!(total);
    progress["active"] = json!(active);
    match now {
        Some(title) if active => {
            json!({"title": title, "step": (completed + 1).min(total), "total": total})
        }
        _ => Value::Null,
    }
}

/// A tool message's `build` is the progress a Struo build or test in its
/// command reported: `command` (`build` or `test`), `state` (`running`,
/// `succeeded` or `failed`), `target`, target counts (`planned`, `done`,
/// `cached`, `failed`), `running` target ids and `tests` case counts. The core
/// clamps `done` to `planned` once a plan is known, nulls `tests` until a case
/// ran, and adds `fraction`, the share of planned targets done (null until a
/// plan is known), `failing`, whether a target or test case failed, and
/// `active`, whether the build still runs in a working thread, so edges
/// animate only live builds. A build this core can't show is dropped, and the
/// edge shows the message's `content`, the same progress in words.
fn present_build(message: &mut Value, working: bool) {
    let Some(build) = message.get_mut("build") else {
        return;
    };
    let count = |key: &str| build[key].as_u64();
    let known = matches!(build["command"].as_str(), Some("build" | "test"))
        && matches!(
            build["state"].as_str(),
            Some("running" | "succeeded" | "failed")
        )
        && ["planned", "done", "cached", "failed"]
            .iter()
            .all(|key| count(key).is_some());
    if !known {
        message.as_object_mut().map(|m| m.remove("build"));
        return;
    }
    let (planned, done) = (count("planned").unwrap_or(0), count("done").unwrap_or(0));
    let failed_targets = count("failed").unwrap_or(0);
    let case = |key: &str| build["tests"][key].as_u64().unwrap_or(0);
    let (passed, failed_cases, skipped) = (case("passed"), case("failed"), case("skipped"));
    let running = build["state"] == "running" && message["toolStatus"] == "running";
    let build = &mut message["build"];
    if planned > 0 {
        build["done"] = json!(done.min(planned));
        build["fraction"] = json!((done.min(planned) as f64) / (planned as f64));
    } else {
        build["fraction"] = Value::Null;
    }
    build["tests"] = if passed + failed_cases + skipped > 0 {
        json!({"passed": passed, "failed": failed_cases, "skipped": skipped})
    } else {
        Value::Null
    };
    build["failing"] = json!(failed_targets > 0 || failed_cases > 0);
    build["active"] = json!(working && running);
}

/// A message's `ui` is a card the model wrote: NSH JavaScript `source` shown
/// in a frame of its `size` class. The core turns the class into the frame's
/// `height` in points, so every edge lays the card out at the same size
/// before it runs, and the card fills that frame instead of measuring
/// itself. A card this core can't show is dropped, and the edge shows the
/// message's `content` as it would any other.
fn present_card(message: &mut Value) {
    let Some(ui) = message.get_mut("ui") else {
        return;
    };
    let height = match ui["size"].as_str() {
        Some("compact") => 120,
        Some("medium") => 240,
        Some("tall") => 400,
        _ => 0,
    };
    let source = ui["source"].as_str().unwrap_or_default();
    if height == 0 || source.is_empty() || source.len() > 256 * 1024 {
        message.as_object_mut().map(|m| m.remove("ui"));
    } else {
        ui["height"] = json!(height);
    }
}

fn thread_id(args: &Value) -> Result<&str> {
    let id = text(args, "id")?;
    if id.len() == 36 && id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
        Ok(id)
    } else {
        Err("Invalid thread")
    }
}

fn message_content(args: &Value) -> Result<&str> {
    let files = attachments(args)?;
    let content = args
        .get("content")
        .and_then(Value::as_str)
        .unwrap_or_default();
    if content.trim().is_empty() && files.is_empty() {
        return Err("Message is empty");
    }
    if content.len() > 16_000 {
        return Err("Message is too long");
    }
    Ok(content)
}

/// Bounded inline files travel with the idempotent message, never as a separate
/// upload that could be orphaned or silently dropped by an offline retry.
fn attachments(args: &Value) -> Result<Vec<Value>> {
    let Some(files) = args.get("attachments") else {
        return Ok(vec![]);
    };
    let files = files.as_array().ok_or("Invalid attachments")?;
    if files.len() > 4 {
        return Err("Attach up to four files");
    }
    for file in files {
        let name = text(file, "name")?;
        let mime = text(file, "mime_type")?;
        let encoded = text(file, "data_base64")?;
        if name.len() > 255
            || name.contains(['/', '\\'])
            || name.chars().any(char::is_control)
            || mime.len() > 127
            || !mime.contains('/')
            || mime.chars().any(char::is_whitespace)
            || encoded.len() > 1_398_104
        {
            return Err("Invalid attachment");
        }
        let data = STANDARD
            .decode(encoded)
            .map_err(|_| "Invalid attachment data")?;
        if data.is_empty() || data.len() > 1024 * 1024 {
            return Err("Files must be between 1 byte and 1 MiB");
        }
    }
    Ok(files.clone())
}

/// A random version 4 UUID, which the server requires for idempotency keys.
pub(crate) fn new_request_id() -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    const HEX: &[u8] = b"0123456789abcdef";
    // Each base64url character of the verifier carries six random bits; keep four.
    let mut digits: Vec<u8> = Pkce::generate()
        .verifier
        .bytes()
        .take(32)
        .map(|b| ALPHABET.iter().position(|a| *a == b).unwrap_or(0) as u8 & 15)
        .collect();
    digits[12] = 4;
    digits[16] = 8 | (digits[16] & 3);
    let hex: String = digits.iter().map(|d| HEX[*d as usize] as char).collect();
    format!(
        "{}-{}-{}-{}-{}",
        &hex[0..8],
        &hex[8..12],
        &hex[12..16],
        &hex[16..20],
        &hex[20..32]
    )
}

/// The runner a new thread runs on: absent for Tuist's own sandbox.
fn runner_id(args: &Value) -> Result<Option<&str>> {
    match args.get("runner_id") {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(id))
            if id.len() == 36 && id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') =>
        {
            Ok(Some(id))
        }
        Some(_) => Err("Invalid runner"),
    }
}
