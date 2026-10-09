//! `once toolchain inspect` - print the project toolchain contract.

use std::path::Path;

use anyhow::Result;
use tokio::io::AsyncWriteExt;

use crate::cli::{Format, Output};
use crate::render;

mod contract;
mod human;
mod lock;
mod mise;
mod platform;

pub async fn inspect(workspace: &Path, output: Output, platform: Option<&str>) -> Result<()> {
    let contract = mise::inspect_workspace(workspace, platform)?;
    let body = match output.format {
        Format::Human => human::render(&contract),
        Format::Json | Format::Toon => render::structured(output.format, &contract)?,
    };

    let mut out = tokio::io::stdout();
    out.write_all(body.as_bytes()).await?;
    out.flush().await?;
    Ok(())
}
