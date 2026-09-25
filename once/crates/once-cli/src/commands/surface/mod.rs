use anyhow::Result;
use tokio::io::AsyncWriteExt;

use crate::cli::{Format, Output};
use crate::render;

mod human;
mod model;

pub async fn print(path: &[&str], output: Output) -> Result<()> {
    let surface = model::load(path)?;
    let body = match output.format {
        Format::Human => human::render(&surface),
        Format::Json | Format::Toon => render::structured(output.format, &surface)?,
    };
    let mut out = tokio::io::stdout();
    out.write_all(body.as_bytes()).await?;
    out.flush().await?;
    Ok(())
}
