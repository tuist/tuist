use std::path::Path;

use anyhow::{bail, Context, Result};
use console::Style;
use once_cas::{TuistAuth, TuistAuthPrompt};
use once_core::Xdg;

use crate::cache_provider::{self, ResolvedCacheProviderConfig};
use crate::cli::Output;

pub async fn login(
    workspace: &Path,
    xdg: &Xdg,
    provider: &str,
    open_browser: bool,
    output: Output,
) -> Result<()> {
    match cache_provider::resolve_auth_provider(workspace, xdg, provider)? {
        ResolvedCacheProviderConfig::Local => {
            bail!("cache provider `{provider}` does not support authentication")
        }
        ResolvedCacheProviderConfig::Tuist(config) => {
            let provider_name = config.provider_name.clone();
            let provider_name_for_prompt = provider_name.clone();
            let server_url = config.url.clone();
            let credentials_root = cache_provider::credentials_root(xdg);
            tokio::task::spawn_blocking(move || {
                let auth = TuistAuth::new(credentials_root, &config);
                let mut handler =
                    |prompt| print_login_prompt(&provider_name_for_prompt, &server_url, &prompt);
                auth.login_with_handler(open_browser, &mut handler)
            })
            .await
            .context("waiting for provider login")??;
            if output.show_human_trailers() {
                println!(
                    "{} {} {}",
                    stdout_brand(),
                    stdout_success("authenticated"),
                    stdout_provider(&provider_name)
                );
            }
            Ok(())
        }
    }
}

pub async fn logout(workspace: &Path, xdg: &Xdg, provider: &str, output: Output) -> Result<()> {
    match cache_provider::resolve_auth_provider(workspace, xdg, provider)? {
        ResolvedCacheProviderConfig::Local => {
            bail!("cache provider `{provider}` does not support authentication")
        }
        ResolvedCacheProviderConfig::Tuist(config) => {
            let provider_name = config.provider_name.clone();
            let credentials_root = cache_provider::credentials_root(xdg);
            let removed = tokio::task::spawn_blocking(move || {
                TuistAuth::new(credentials_root, &config).logout()
            })
            .await
            .context("waiting for provider logout")??;
            if output.show_human_trailers() {
                if removed {
                    println!(
                        "{} {} {}",
                        stdout_brand(),
                        stdout_success("cleared session for"),
                        stdout_provider(&provider_name)
                    );
                } else {
                    println!(
                        "{} {} {}",
                        stdout_brand(),
                        stdout_dim("no stored session for"),
                        stdout_provider(&provider_name)
                    );
                }
            }
            Ok(())
        }
    }
}

fn print_login_prompt(provider_name: &str, server_url: &str, prompt: &TuistAuthPrompt) {
    eprintln!();
    eprintln!("{} {}", stderr_brand(), stderr_heading("Auth Login"));
    eprintln!(
        "  {} {}",
        stderr_label("provider"),
        stderr_provider(provider_name)
    );
    eprintln!("  {} {}", stderr_label("server"), stderr_url(server_url));
    eprintln!(
        "  {} {}",
        stderr_label("callback"),
        stderr_url(&prompt.redirect_uri)
    );
    if prompt.opens_browser {
        eprintln!(
            "  {} {}",
            stderr_label("browser"),
            stderr_accent("opening your default browser")
        );
        eprintln!(
            "  {} {}",
            stderr_label("fallback"),
            stderr_dim("open this URL if no browser window appears")
        );
    } else {
        eprintln!(
            "  {} {}",
            stderr_label("browser"),
            stderr_dim("disabled, open this URL to continue")
        );
    }
    eprintln!(
        "  {} {}",
        stderr_label("url"),
        stderr_url(&prompt.authorize_url)
    );
    eprintln!();
}

fn paint(value: &str, for_stderr: bool, style: impl FnOnce(Style) -> Style) -> String {
    let base = if for_stderr {
        Style::new().for_stderr()
    } else {
        Style::new()
    };
    style(base).apply_to(value).to_string()
}

fn stderr_brand() -> String {
    paint("once", true, |style| style.black().on_cyan().bold())
}

fn stderr_heading(value: &str) -> String {
    paint(value, true, Style::bold)
}

fn stderr_label(value: &str) -> String {
    paint(value, true, |style| style.cyan().bold())
}

fn stderr_provider(value: &str) -> String {
    paint(value, true, |style| style.green().bold())
}

fn stderr_url(value: &str) -> String {
    paint(value, true, |style| style.yellow().underlined())
}

fn stderr_accent(value: &str) -> String {
    paint(value, true, Style::bold)
}

fn stderr_dim(value: &str) -> String {
    paint(value, true, Style::dim)
}

fn stdout_brand() -> String {
    paint("once", false, |style| style.black().on_cyan().bold())
}

fn stdout_success(value: &str) -> String {
    paint(value, false, |style| style.green().bold())
}

fn stdout_provider(value: &str) -> String {
    paint(value, false, |style| style.cyan().bold())
}

fn stdout_dim(value: &str) -> String {
    paint(value, false, Style::dim)
}
