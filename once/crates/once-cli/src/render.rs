use anyhow::Result;
use serde::Serialize;

use crate::cli::Format;

pub fn structured<T: Serialize>(format: Format, value: &T) -> Result<String> {
    let body = match format {
        Format::Human => unreachable!("human rendering is handled by the caller"),
        Format::Json => serde_json::to_string(value)?,
        Format::Toon => toon_rust::to_string(value)?,
    };
    Ok(format!("{body}\n"))
}
