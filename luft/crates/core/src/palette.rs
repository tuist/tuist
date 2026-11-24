//! The command palette (⌘K): what the person can jump to for what they typed,
//! best match first. Every result carries the internal route the edge passes
//! to `navigate`, so the palette only finds; navigation stays in one place.
use serde_json::{Value, json};

use crate::Tab;

/// Results shown for a query; an empty query shows the destinations, New
/// conversation and the most recent threads.
const LIMIT: usize = 20;
const RECENT_THREADS: usize = 5;

/// Ranks destinations, New conversation, the inbox's `threads` (shaped like the
/// `threads` operation) and `lounges` (shaped like the `lounges` operation, or null
/// before it loaded) for `query`. `labels` maps destination IDs and
/// `new_conversation` to the edge's localized titles, which are matched and
/// returned; missing ones fall back to English.
pub fn palette(query: &str, labels: &Value, threads: &Value, lounges: &Value) -> Value {
    let label = |id: &str, fallback: &str| {
        labels
            .get(id)
            .and_then(Value::as_str)
            .unwrap_or(fallback)
            .to_string()
    };
    let mut items: Vec<Value> = Tab::ALL
        .iter()
        .map(|tab| {
            let fallback = match tab {
                Tab::Threads => "Threads",
                Tab::Lounges => "Lounges",
                Tab::Dms => "DMs",
                Tab::Profile => "Profile",
            };
            json!({"kind":"destination","id":tab.id(),"title":label(tab.id(), fallback),
                   "url":format!("/{}", tab.id())})
        })
        .collect();
    items.push(json!({"kind":"action","id":"new_conversation",
        "title":label("new_conversation", "New conversation"),"url":"/threads/new"}));
    let fixed = items.len();
    for thread in threads["threads"].as_array().into_iter().flatten() {
        let Some(id) = thread["id"].as_str() else {
            continue;
        };
        let title = thread["title"]
            .as_str()
            .or(thread["goal"].as_str())
            .filter(|t| !t.trim().is_empty());
        items.push(
            json!({"kind":"thread","id":id,"title":title,"state":thread["state"],
            "section":thread["section"],"url":format!("/threads/{id}")}),
        );
    }
    for (key, kind) in [("lounges", "lounge"), ("directs", "dm")] {
        for lounge in lounges[key].as_array().into_iter().flatten() {
            let Some(id) = lounge["id"].as_str() else {
                continue;
            };
            items.push(json!({"kind":kind,"id":id,"title":lounge["title"],
                "unread":lounge["unread"],"url":format!("/{kind}s/{id}")}));
        }
    }

    let query = query.trim().to_lowercase();
    if query.is_empty() {
        let recent = items
            .iter()
            .skip(fixed)
            .filter(|i| i["kind"] == "thread")
            .take(RECENT_THREADS)
            .cloned();
        let items: Vec<Value> = items[..fixed].iter().cloned().chain(recent).collect();
        return json!({"items":items});
    }
    let words: Vec<&str> = query.split_whitespace().collect();
    let mut ranked: Vec<(u8, usize, Value)> = items
        .into_iter()
        .enumerate()
        .filter_map(|(order, item)| {
            let title = item["title"].as_str().unwrap_or_default().to_lowercase();
            // "rel" finds #releases, and "#rel" only lounges; ranking ignores the #.
            if !words.iter().all(|w| title.contains(w)) {
                return None;
            }
            let bare = title.trim_start_matches('#');
            let score = if bare == query.trim_start_matches('#') {
                0
            } else if bare.starts_with(query.trim_start_matches('#')) {
                1
            } else if title
                .split(|c: char| !c.is_alphanumeric())
                .any(|word| word.starts_with(words[0].trim_start_matches('#')))
            {
                2
            } else {
                3
            };
            Some((score, order, item))
        })
        .collect();
    ranked.sort_by_key(|(score, order, _)| (*score, *order));
    let items: Vec<Value> = ranked
        .into_iter()
        .take(LIMIT)
        .map(|(_, _, item)| item)
        .collect();
    json!({"items":items})
}

#[cfg(test)]
mod tests {
    use super::*;

    const RELEASE: &str = "11111111-1111-1111-1111-111111111111";
    const DM: &str = "22222222-2222-2222-2222-222222222222";

    fn threads() -> Value {
        json!({"threads":[
            {"id":"a","title":"Fix the flaky release test","section":"in_progress","state":"running"},
            {"id":"b","title":null,"goal":"Release notes for 4.2","section":"recent"},
            {"id":"c","title":"Prerelease checklist","section":"recent"},
            {"id":"d","title":"Release","section":"archived"},
        ]})
    }

    fn lounges() -> Value {
        json!({"available":true,
            "lounges":[{"id":RELEASE,"kind":"lounge","title":"#releases","unread":3}],
            "directs":[{"id":DM,"kind":"direct","title":"ana, marek","unread":0}]})
    }

    fn ids(result: &Value) -> Vec<&str> {
        result["items"]
            .as_array()
            .unwrap()
            .iter()
            .map(|i| i["id"].as_str().unwrap())
            .collect()
    }

    #[test]
    fn an_empty_query_lists_destinations_then_recent_threads() {
        let result = palette("  ", &json!({}), &threads(), &lounges());
        assert_eq!(
            ids(&result),
            [
                "threads",
                "lounges",
                "dms",
                "profile",
                "new_conversation",
                "a",
                "b",
                "c",
                "d"
            ]
        );
        assert_eq!(result["items"][4]["url"], "/threads/new");
        assert_eq!(result["items"][3]["url"], "/profile");
    }

    #[test]
    fn ranks_exact_then_prefix_then_word_then_substring_matches() {
        let result = palette("Release", &json!({}), &threads(), &lounges());
        // Exact title, then titles starting with it (the goal stands in for a
        // missing title; the lounge matches without its #), then a word starting
        // with it, then the substring inside "Prerelease".
        assert_eq!(ids(&result), ["d", "b", RELEASE, "a", "c"]);
        assert_eq!(result["items"][1]["title"], "Release notes for 4.2");
        assert_eq!(result["items"][2]["url"], format!("/lounges/{RELEASE}"));
    }

    #[test]
    fn every_word_must_match_and_dms_route_to_their_tab() {
        let result = palette("marek ana", &json!({}), &threads(), &lounges());
        assert_eq!(ids(&result), [DM]);
        assert_eq!(result["items"][0]["url"], format!("/dms/{DM}"));
        assert!(ids(&palette("flaky notes", &json!({}), &threads(), &lounges())).is_empty());
        assert_eq!(
            ids(&palette("#rel", &json!({}), &threads(), &lounges())),
            [RELEASE]
        );
    }

    #[test]
    fn matches_the_edges_localized_labels() {
        let labels = json!({"threads":"Fäden","new_conversation":"Neue Unterhaltung"});
        let result = palette("neue", &labels, &json!({}), &Value::Null);
        assert_eq!(ids(&result), ["new_conversation"]);
        assert_eq!(result["items"][0]["title"], "Neue Unterhaltung");
        assert_eq!(
            ids(&palette("fäd", &labels, &json!({}), &Value::Null)),
            ["threads"]
        );
        // Unlabelled destinations keep their English titles.
        assert_eq!(
            ids(&palette("dms", &labels, &json!({}), &Value::Null)),
            ["dms"]
        );
    }
}
