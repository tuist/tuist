//! Looping people into a conversation from its composer. Typing `@` offers
//! the organization's people; what mentioning them does depends on where:
//! a thread lets them read and prompt it once the message is sent (the server
//! loops in whoever the message mentions), a lounge suggests inviting people who
//! aren't in it yet, a new lounge invites them, and a direct conversation keeps
//! a plain mention.
//!
//! `compose` is pure and keeps no state, so edges call it on every edit
//! without waiting behind the client's serialized network operations.
use serde_json::{Value, json};

/// How many people the composer suggests for one `@` query.
const SUGGESTIONS: usize = 6;

/// See `compose` in the crate README for the contract.
pub fn compose(input: &Value) -> Value {
    let context = input["context"].as_str().unwrap_or("direct");
    let mut content = input["content"].as_str().unwrap_or_default().to_string();
    let people: Vec<&Value> = input["people"]
        .as_array()
        .map(|p| p.iter().filter(|p| handle(p).is_some()).collect())
        .unwrap_or_default();
    let members: Vec<u64> = input["members"]
        .as_array()
        .map(|m| m.iter().filter_map(Value::as_u64).collect())
        .unwrap_or_default();
    let length = utf16_len(&content);
    let mut cursor = input["cursor"]
        .as_u64()
        .map_or(length, |c| c as usize)
        .min(length);

    if let Some(id) = input["pick"].as_u64()
        && let Some(person) = people.iter().find(|p| p["id"].as_u64() == Some(id))
        && let Some((start, end)) = query(&content, cursor).map(|q| (q.1, q.2))
    {
        let mention = format!("@{} ", handle(person).unwrap_or_default());
        let (from, to) = (byte_at(&content, start - 1), byte_at(&content, end));
        // A space already after the query separates the mention from what follows.
        let mention = if content[to..].starts_with(' ') {
            mention.trim_end()
        } else {
            &mention
        };
        content.replace_range(from..to, mention);
        cursor = start - 1 + utf16_len(mention);
        if content[byte_at(&content, cursor)..].starts_with(' ') {
            cursor += 1;
        }
    }

    let mentioned: Vec<&Value> = mentions(&content)
        .iter()
        .filter_map(|h| {
            people
                .iter()
                .find(|p| handle(p).is_some_and(|ph| ph.eq_ignore_ascii_case(h)))
                .copied()
        })
        .collect();
    let absent: Vec<&Value> = mentioned
        .iter()
        .filter(|p| p["id"].as_u64().is_none_or(|id| !members.contains(&id)))
        .copied()
        .collect();
    let (loop_in, invite) = match context {
        "new_thread" | "thread" => (absent, vec![]),
        "new_lounge" => (mentioned.clone(), vec![]),
        "lounge" => (vec![], absent),
        _ => (vec![], vec![]),
    };

    let query = query(&content, cursor);
    let (suggestions, matches) = query
        .as_ref()
        .map(|(text, _, _)| suggest(&people, &mentioned, text))
        .unwrap_or_default();
    json!({
        "content": content,
        "cursor": cursor,
        "query": query.map(|(text, start, end)| json!({"text": text, "start": start, "end": end})),
        "suggestions": suggestions,
        "matches": matches,
        "mentioned": mentioned,
        "loop_in": loop_in,
        "invite": invite,
    })
}

/// The handles `text` mentions, lowercased, in order and without repeats.
/// Matches the server's `Tuist.Threads.mentions/1`: `@` at the start or after
/// anything but a letter, digit, `_`, `.`, `@` or `-`, then a handle that
/// starts and ends with a letter or digit, so email addresses don't count.
pub fn mentions(text: &str) -> Vec<String> {
    let chars: Vec<char> = text.chars().collect();
    let mut found: Vec<String> = Vec::new();
    for (index, c) in chars.iter().enumerate() {
        if *c != '@' || (index > 0 && !boundary(chars[index - 1])) {
            continue;
        }
        let handle: String = chars[index + 1..]
            .iter()
            .take_while(|c| handle_char(**c))
            .collect::<String>()
            .trim_end_matches('-')
            .to_ascii_lowercase();
        if handle.starts_with(|c: char| c.is_ascii_alphanumeric()) && !found.contains(&handle) {
            found.push(handle);
        }
    }
    found
}

/// The `@` query the cursor (a UTF-16 offset) is in: its text and the UTF-16
/// range after the `@` up to the end of the handle being typed.
fn query(content: &str, cursor: usize) -> Option<(String, usize, usize)> {
    let chars: Vec<(usize, char)> = utf16_chars(content).collect();
    let at = chars
        .iter()
        .position(|(offset, _)| *offset >= cursor)
        .unwrap_or(chars.len());
    let mut start = at;
    while start > 0 && handle_char(chars[start - 1].1) {
        start -= 1;
    }
    if start == 0 || chars[start - 1].1 != '@' || (start > 1 && !boundary(chars[start - 2].1)) {
        return None;
    }
    let mut end = at;
    while end < chars.len() && handle_char(chars[end].1) {
        end += 1;
    }
    let offset = |i: usize| chars.get(i).map_or(utf16_len(content), |(o, _)| *o);
    let text = chars[start..at].iter().map(|(_, c)| c).collect();
    Some((text, offset(start), offset(end)))
}

/// People whose handle starts with `query` first, then those containing it,
/// leaving out anyone already mentioned, and how many match. Suggests nobody
/// until a name is typed or while more than `SUGGESTIONS` match, so a large
/// organization never shows an arbitrary few; edges ask to keep typing instead.
fn suggest(people: &[&Value], mentioned: &[&Value], query: &str) -> (Vec<Value>, usize) {
    let query = query.to_ascii_lowercase();
    let mut matches: Vec<(bool, String, &Value)> = people
        .iter()
        .filter(|p| !mentioned.iter().any(|m| m["id"] == p["id"]))
        .filter_map(|p| {
            let handle = handle(p)?.to_ascii_lowercase();
            handle
                .contains(&query)
                .then(|| (!handle.starts_with(&query), handle, *p))
        })
        .collect();
    if query.is_empty() || matches.len() > SUGGESTIONS {
        return (vec![], matches.len());
    }
    matches.sort_by(|a, b| (a.0, &a.1).cmp(&(b.0, &b.1)));
    let count = matches.len();
    (
        matches.into_iter().map(|(_, _, p)| p.clone()).collect(),
        count,
    )
}

fn handle(person: &Value) -> Option<&str> {
    person["handle"].as_str().filter(|h| !h.is_empty())
}

fn handle_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '-'
}

fn boundary(c: char) -> bool {
    !(c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '@' | '-'))
}

fn utf16_len(text: &str) -> usize {
    text.encode_utf16().count()
}

/// Each character with its UTF-16 offset, the unit Swift's and Kotlin's text
/// fields report cursors in.
fn utf16_chars(text: &str) -> impl Iterator<Item = (usize, char)> + '_ {
    text.chars().scan(0, |offset, c| {
        let at = *offset;
        *offset += c.len_utf16();
        Some((at, c))
    })
}

/// The byte index of a UTF-16 offset that falls on a character boundary.
fn byte_at(text: &str, offset: usize) -> usize {
    let mut units = 0;
    for (byte, c) in text.char_indices() {
        if units >= offset {
            return byte;
        }
        units += c.len_utf16();
    }
    text.len()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn people() -> Value {
        json!([
            {"id": 2, "handle": "ben", "online": true},
            {"id": 3, "handle": "Bea-Marie", "online": false},
            {"id": 4, "handle": "rob", "online": false},
        ])
    }

    fn run(context: &str, content: &str, extra: Value) -> Value {
        let mut input =
            json!({"context": context, "content": content, "people": people(), "members": [1, 4]});
        for (key, value) in extra.as_object().unwrap() {
            input[key] = value.clone();
        }
        compose(&input)
    }

    fn handles(value: &Value) -> Vec<&str> {
        value
            .as_array()
            .unwrap()
            .iter()
            .map(|p| p["handle"].as_str().unwrap())
            .collect()
    }

    #[test]
    fn mentions_match_the_servers_rule() {
        assert_eq!(
            mentions("@Ana, ask @ben-c (not ana@ben.dev, x@cai or @-dan) about @ana again."),
            ["ana", "ben-c"]
        );
    }

    #[test]
    fn typing_after_at_suggests_prefix_matches_before_other_matches() {
        let result = run("thread", "ask @b", json!({}));
        assert_eq!(result["query"], json!({"text": "b", "start": 5, "end": 6}));
        // "rob" contains "b" but doesn't start with it, so it comes last.
        assert_eq!(handles(&result["suggestions"]), ["Bea-Marie", "ben", "rob"]);
        assert_eq!(result["matches"], 3);
        // A bare `@` suggests nobody yet, but counts who could be mentioned.
        let bare = run("thread", "ask @", json!({}));
        assert_eq!(bare["query"]["text"], "");
        assert!(handles(&bare["suggestions"]).is_empty());
        assert_eq!(bare["matches"], 3);
        // An email address isn't a mention being typed.
        assert!(run("thread", "mail ana@b", json!({}))["query"].is_null());
        // Nor is text after the handle ends.
        assert!(run("thread", "@ben ", json!({}))["query"].is_null());
    }

    #[test]
    fn picking_replaces_the_query_at_the_cursor_and_counts_utf16() {
        // "🚀" is two UTF-16 units, as Swift and Kotlin count cursors.
        let result = run("direct", "🚀 @be and more", json!({"cursor": 6, "pick": 3}));
        assert_eq!(result["content"], "🚀 @Bea-Marie and more");
        assert_eq!(result["cursor"], 14);
        assert!(result["query"].is_null());
        let appended = run("direct", "hi @r", json!({"pick": 4}));
        assert_eq!(appended["content"], "hi @rob ");
        assert_eq!(appended["cursor"], 8);
    }

    #[test]
    fn each_context_decides_what_a_mention_does() {
        // Rob (4) is already a member; Ben isn't. Unknown handles do nothing.
        let content = "@BEN @rob @nobody";
        assert_eq!(
            handles(&run("thread", content, json!({}))["loop_in"]),
            ["ben"]
        );
        assert_eq!(
            handles(&run("new_thread", content, json!({}))["loop_in"]),
            ["ben"]
        );
        let lounge = run("lounge", content, json!({}));
        assert_eq!(handles(&lounge["invite"]), ["ben"]);
        assert_eq!(lounge["loop_in"], json!([]));
        assert_eq!(
            handles(&run("new_lounge", content, json!({}))["loop_in"]),
            ["ben", "rob"]
        );
        let direct = run("direct", content, json!({}));
        assert_eq!(handles(&direct["mentioned"]), ["ben", "rob"]);
        assert_eq!(
            (direct["loop_in"].clone(), direct["invite"].clone()),
            (json!([]), json!([]))
        );
    }

    #[test]
    fn people_already_mentioned_are_not_suggested_again() {
        let result = run("thread", "@ben and @b", json!({}));
        assert_eq!(handles(&result["suggestions"]), ["Bea-Marie", "rob"]);
    }

    #[test]
    fn too_many_matches_suggest_nobody_until_the_name_narrows_them() {
        let people: Vec<Value> = (0..7)
            .map(|i| json!({"id": 10 + i, "handle": format!("sam{i}")}))
            .chain([json!({"id": 30, "handle": "sara"})])
            .collect();
        let input =
            |content: &str| json!({"context": "thread", "content": content, "people": people});
        let broad = compose(&input("@sa"));
        assert!(handles(&broad["suggestions"]).is_empty());
        assert_eq!(broad["matches"], 8);
        let narrow = compose(&input("@sar"));
        assert_eq!(handles(&narrow["suggestions"]), ["sara"]);
        assert_eq!(narrow["matches"], 1);
    }
}
