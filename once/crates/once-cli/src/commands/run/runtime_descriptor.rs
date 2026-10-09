use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize)]
pub(super) struct RuntimeDescriptor {
    pub(super) kind: String,
    pub(super) subject: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) session: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) rpc: Option<RuntimeRpcDescriptor>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub(super) capabilities: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub(super) interfaces: Vec<RuntimeInterface>,
}

#[derive(Debug, Clone, Serialize)]
pub(super) struct RuntimeRpcDescriptor {
    transport: &'static str,
    socket: String,
}

impl RuntimeRpcDescriptor {
    pub(super) fn new(socket: String) -> Self {
        Self {
            transport: "jsonrpc",
            socket,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct RuntimeInterface {
    pub(super) name: String,
    pub(super) kind: String,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub(super) argv: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(super) description: Option<String>,
}

pub(super) fn runtime_descriptor(
    target_id: &str,
    target: &once_frontend::Target,
) -> Result<Option<RuntimeDescriptor>> {
    if target.kind == "runtime_task"
        || target.kind == "runner_task"
        || target.kind == "runtime_script"
    {
        return runtime_task_descriptor(target_id, target).map(Some);
    }

    Ok(None)
}

fn runtime_task_descriptor(
    target_id: &str,
    target: &once_frontend::Target,
) -> Result<RuntimeDescriptor> {
    let runtime = target
        .attrs
        .get("runtime")
        .ok_or_else(|| anyhow::anyhow!("runtime_task {} has no runtime", target.id()))?
        .to_string();
    let subject = target
        .attrs
        .get("runtime_target")
        .or_else(|| target.attrs.get("runner_target"))
        .cloned()
        .unwrap_or_else(|| target_id.to_string());
    let capabilities = parse_json_attr::<Vec<String>>(target, "runtime_capabilities_json")?
        .or(parse_json_attr::<Vec<String>>(
            target,
            "runner_capabilities_json",
        )?)
        .unwrap_or_default();
    let interfaces = parse_json_attr::<Vec<RuntimeInterface>>(target, "runtime_interfaces_json")?
        .or(parse_json_attr::<Vec<RuntimeInterface>>(
            target,
            "runner_interfaces_json",
        )?)
        .unwrap_or_default();
    Ok(RuntimeDescriptor {
        kind: runtime,
        subject,
        session: None,
        rpc: None,
        capabilities,
        interfaces,
    })
}

fn parse_json_attr<T>(target: &once_frontend::Target, name: &str) -> Result<Option<T>>
where
    T: serde::de::DeserializeOwned,
{
    target
        .attrs
        .get(name)
        .map(|value| {
            serde_json::from_str::<T>(value)
                .with_context(|| format!("parsing {name} for {}", target.id()))
        })
        .transpose()
}
