use std::fmt::Write as _;

use super::contract::ToolchainContract;

pub(super) fn render(contract: &ToolchainContract) -> String {
    let lock = contract.lock.as_deref().unwrap_or("missing");
    let mut out = format!(
        "source: {}\nconfig: {}\nlock: {}\nplatform: {} ({}/{})\nfingerprint: {}\n",
        contract.source,
        contract.config,
        lock,
        contract.platform.mise,
        contract.platform.os,
        contract.platform.arch,
        contract.fingerprint
    );

    if contract.tools.is_empty() {
        out.push_str("tools: none\n");
    } else {
        out.push_str("tools:\n");
        for tool in &contract.tools {
            let request = format_toml_value(&tool.request);
            match &tool.locked {
                Some(locked) => {
                    writeln!(out, "  {} {} -> {}", tool.name, request, locked.version)
                        .expect("writing to string cannot fail");
                }
                None => {
                    writeln!(out, "  {} {}", tool.name, request)
                        .expect("writing to string cannot fail");
                }
            }
        }
    }

    if !contract.env.is_empty() {
        out.push_str("env:\n");
        for (key, value) in &contract.env {
            writeln!(out, "  {key} = {}", format_toml_value(value))
                .expect("writing to string cannot fail");
        }
    }

    out
}

fn format_toml_value(value: &toml::Value) -> String {
    value
        .as_str()
        .map_or_else(|| value.to_string(), ToOwned::to_owned)
}
