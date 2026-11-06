//! A conservative, shared JSON Schema-to-native-controls projection.
use serde_json::{Value, json};

pub(crate) fn project(schema: &Value) -> Value {
    let mut fields = Vec::new();
    let supported = object(schema, &[], &mut fields, 0);
    json!({"supported":supported,"fields":if supported { fields } else { Vec::new() }})
}
fn object(schema: &Value, path: &[String], fields: &mut Vec<Value>, depth: usize) -> bool {
    if depth > 4 || schema["type"] != "object" || unsupported(schema) {
        return false;
    }
    let properties = match schema.get("properties") {
        None => {
            if !path.is_empty() || schema["minProperties"].as_u64().unwrap_or(0) > 0 {
                return false;
            }
            return schema
                .get("required")
                .and_then(Value::as_array)
                .is_none_or(Vec::is_empty);
        }
        Some(v) => match v.as_object() {
            Some(v) => v,
            None => return false,
        },
    };
    if properties.is_empty()
        && (!path.is_empty() || schema["minProperties"].as_u64().unwrap_or(0) > 0)
    {
        return false;
    }
    let required = schema["required"].as_array();
    if required.is_some_and(|r| {
        r.iter()
            .any(|key| key.as_str().is_none_or(|k| !properties.contains_key(k)))
    }) {
        return false;
    }
    for (key, value) in properties {
        if fields.len() >= 32 {
            return false;
        }
        let mut path = path.to_vec();
        path.push(key.clone());
        let needed = required.is_some_and(|items| items.contains(&Value::String(key.clone())));
        if value["type"] == "object" {
            // Optional object groups have conditional requiredness: fall back rather than pretend.
            if !needed || !object(value, &path, fields, depth + 1) {
                return false;
            }
            continue;
        }
        if unsupported(value) {
            return false;
        }
        let kind = match value["type"].as_str() {
            Some("string") => match value.get("enum") {
                Some(options)
                    if options.as_array().is_some_and(|o| {
                        !o.is_empty() && o.len() <= 100 && o.iter().all(Value::is_string)
                    }) =>
                {
                    "enum"
                }
                Some(_) => return false,
                None if value["format"] == "date" => "date",
                None if value["maxLength"].as_u64().unwrap_or(256) > 256 => "text",
                None => "string",
            },
            Some("boolean") => "boolean",
            Some("integer") => "integer",
            Some("number") => "number",
            _ => return false,
        };
        let mut field = json!({"path":path,"kind":kind,"title":value["title"].as_str().unwrap_or(key),"description":value["description"].as_str().unwrap_or(""),"required":needed});
        for (source, target) in [
            ("enum", "options"),
            ("default", "default"),
            ("minimum", "minimum"),
            ("maximum", "maximum"),
            ("minLength", "min_length"),
            ("maxLength", "max_length"),
        ] {
            if let Some(value) = value.get(source) {
                field[target] = value.clone();
            }
        }
        fields.push(field);
    }
    true
}
fn unsupported(schema: &Value) -> bool {
    [
        "$ref",
        "oneOf",
        "anyOf",
        "allOf",
        "not",
        "if",
        "then",
        "else",
        "dependencies",
        "dependentSchemas",
        "patternProperties",
        "const",
    ]
    .iter()
    .any(|key| schema.get(key).is_some())
        || (schema.get("enum").is_some() && schema["type"] != "string")
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn projects_native_controls_and_required_paths() {
        let form = project(
            &json!({"type":"object","required":["name"],"properties":{"name":{"type":"string","title":"Name"},"reason":{"type":"string","maxLength":2000},"ready":{"type":"boolean"},"date":{"type":"string","format":"date"},"currency":{"type":"string","enum":["EUR","USD"]}}}),
        );
        assert_eq!(form["supported"], true);
        assert_eq!(form["fields"].as_array().unwrap().len(), 5);
        assert!(
            form["fields"]
                .as_array()
                .unwrap()
                .iter()
                .any(|f| f["path"] == json!(["name"]) && f["required"] == true)
        );
    }
    #[test]
    fn fails_closed_for_unrenderable_contracts() {
        for schema in [
            json!({"type":"object","anyOf":[]}),
            json!({"type":"object","properties":{"list":{"type":"array"}}}),
            json!({"type":"object","required":["missing"]}),
            json!({"type":"object","properties":{"group":{"type":"object"}}}),
        ] {
            assert_eq!(project(&schema)["supported"], false);
        }
    }
    #[test]
    fn no_input_workflows_need_no_fake_fields() {
        assert_eq!(
            project(&json!({"type":"object"})),
            json!({"supported":true,"fields":[]})
        );
    }
}
