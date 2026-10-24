//! Data-only render contract. Unsupported or malformed cards never break history.
use serde::{Deserialize, Deserializer, Serialize};
use serde_json::Value;

#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Component {
    #[serde(rename = "type")]
    kind: String,
    version: u32,
    data: Table,
    actions: Vec<Action>,
    fallback: String,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Table {
    title: String,
    columns: Vec<String>,
    rows: Vec<Vec<String>>,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Action {
    id: String,
    label: String,
}

impl Component {
    fn valid(&self) -> bool {
        self.kind == "result_table"
            && self.version == 1
            && text(&self.data.title, 120)
            && (1..=3).contains(&self.data.columns.len())
            && self.data.columns.iter().all(|column| text(column, 160))
            && (1..=5).contains(&self.data.rows.len())
            && self.data.rows.iter().all(|row| {
                row.len() == self.data.columns.len()
                    && row.iter().all(|cell| cell.chars().count() <= 160)
            })
            && text(&self.fallback, 4_000)
            && self.actions.len() == 1
            && self.actions[0].id == "show_evidence"
            && text(&self.actions[0].label, 40)
    }

    pub(super) fn allows(&self, action: &str) -> bool {
        action == "show_evidence" && self.actions.iter().any(|item| item.id == action)
    }
}

fn text(value: &str, max: usize) -> bool {
    !value.trim().is_empty() && value.chars().count() <= max
}

pub(super) fn deserialize<'de, D>(deserializer: D) -> Result<Option<Component>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Value::deserialize(deserializer)?;
    Ok(serde_json::from_value::<Component>(value)
        .ok()
        .filter(Component::valid))
}

#[cfg(test)]
#[path = "orbit_components_tests.rs"]
mod tests;
