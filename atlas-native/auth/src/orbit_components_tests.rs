use crate::orbit::Message;
use serde_json::{Value, json};

fn card() -> Value {
    json!({"type":"result_table","version":1,"data":{"title":"Accounts","columns":["Name"],"rows":[["Northstar"]]},"actions":[{"id":"show_evidence","label":"View source"}],"fallback":"Northstar"})
}

fn message(component: Value) -> Message {
    serde_json::from_value(json!({"id":"tool-1","kind":"tool","body":"","author_name":"Assistant","inserted_at":"2026-10-22T12:00:00Z","tool_status":"succeeded","tool_output":"original evidence","component":component})).unwrap()
}

#[test]
fn forwards_only_the_supported_server_card_without_inventing_data() {
    let value = message(card());
    assert_eq!(serde_json::to_value(&value).unwrap()["component"], card());
    assert!(value.component.unwrap().allows("show_evidence"));
}

#[test]
fn account_cards_require_the_fixed_field_value_shape() {
    let mut value = card();
    value["type"] = json!("account_card");
    assert!(message(value.clone()).component.is_none());
    value["data"]["columns"] = json!(["Field", "Value"]);
    value["data"]["rows"] = json!([["Domain", "northstar.example"], ["Status", "active"]]);
    assert!(message(value.clone()).component.is_some());
    value["data"]["url"] = json!("https://example.org");
    assert!(message(value).component.is_none());
}

#[test]
fn malformed_or_newer_cards_preserve_the_original_transcript() {
    let mut bad = vec![Value::Null, json!("not a card"), json!({})];
    let mut value = card();
    value["version"] = json!(2);
    bad.push(value);
    let mut value = card();
    value["script"] = json!("fetch('https://evil.example')");
    bad.push(value);
    let mut value = card();
    value["data"]["rows"] = json!([["wrong", "width"]]);
    bad.push(value);
    let mut value = card();
    value["data"]["rows"] = json!([["x".repeat(161)]]);
    bad.push(value);
    let mut value = card();
    value["actions"][0]["id"] = json!("execute_tool");
    bad.push(value);
    let mut value = card();
    value["actions"][0]["url"] = json!("https://evil.example");
    bad.push(value);
    for value in bad {
        let message = message(value);
        assert!(message.component.is_none());
        assert_eq!(message.tool_output, "original evidence");
    }
}

#[test]
fn cards_cannot_expand_the_renderer_limits() {
    for path in ["columns", "rows"] {
        let mut value = card();
        value["data"][path] = if path == "columns" {
            json!(["a", "b", "c", "d"])
        } else {
            json!([["a"], ["b"], ["c"], ["d"], ["e"], ["f"]])
        };
        assert!(message(value).component.is_none());
    }
    let mut value = card();
    value["data"]["rows"] = json!([["汉".repeat(160)]]);
    assert!(message(value).component.is_some());
}
