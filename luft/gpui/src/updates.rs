use std::sync::{Arc, Mutex};

use gpui::{AnyWindowHandle, App, AsyncApp, Global, PromptLevel, actions};
use tuist_updater::PreparedUpdate;

actions!(tuist_updates, [CheckForUpdates]);

/// The installer runs only after the event loop exits and Instance is dropped.
pub type PendingInstall = Arc<Mutex<Option<PreparedUpdate>>>;

pub struct UpdateState {
    phase: Option<&'static str>,
    pending: PendingInstall,
}

impl Global for UpdateState {}

pub fn init(window: AnyWindowHandle, pending: PendingInstall, cx: &mut App) {
    cx.set_global(UpdateState {
        phase: None,
        pending,
    });
    cx.on_action(move |_: &CheckForUpdates, cx| check(window, true, cx));
    check(window, false, cx);
}

pub fn button_label(cx: &App) -> &'static str {
    cx.try_global::<UpdateState>()
        .and_then(|state| state.phase)
        .unwrap_or("Check for updates…")
}

fn check(window: AnyWindowHandle, manual: bool, cx: &mut App) {
    if cx.global::<UpdateState>().phase.is_some() {
        return;
    }
    cx.global_mut::<UpdateState>().phase = Some("Checking for updates…");
    cx.spawn(async move |cx| {
        let result = cx
            .background_executor()
            .spawn(async {
                tuist_updater::availability().map_err(anyhow::Error::msg)?;
                tuist_updater::check()
            })
            .await;
        match result {
            Ok(Some(update)) => {
                let message = format!("Tuist {} is available", update.version());
                let detail = update.notes().unwrap_or("A new version of Tuist is ready.");
                let answer = window.update(cx, |_, window, cx| {
                    window.prompt(
                        PromptLevel::Info,
                        &message,
                        Some(detail),
                        &["Install update and restart", "Later"],
                        cx,
                    )
                });
                if let Ok(answer) = answer
                    && answer.await == Ok(0)
                {
                    cx.update(|cx| {
                        cx.global_mut::<UpdateState>().phase = Some("Downloading update…");
                    });
                    match cx
                        .background_executor()
                        .spawn(async move { update.download() })
                        .await
                    {
                        Ok(prepared) => {
                            cx.update(|cx| {
                                *cx.global::<UpdateState>().pending.lock().unwrap() =
                                    Some(prepared);
                                cx.quit();
                            });
                            return;
                        }
                        Err(error) => {
                            notice(
                                window,
                                "Update could not be downloaded",
                                &error.to_string(),
                                cx,
                            )
                            .await;
                        }
                    }
                }
            }
            Ok(None) if manual => {
                notice(
                    window,
                    "Tuist is up to date",
                    "You have the latest version.",
                    cx,
                )
                .await;
            }
            Err(error) if manual => {
                notice(window, "Updates unavailable", &error.to_string(), cx).await;
            }
            _ => {}
        }
        cx.update(|cx| cx.global_mut::<UpdateState>().phase = None);
    })
    .detach();
}

async fn notice(window: AnyWindowHandle, title: &str, detail: &str, cx: &mut AsyncApp) {
    if let Ok(answer) = window.update(cx, |_, window, cx| {
        window.prompt(PromptLevel::Info, title, Some(detail), &["OK"], cx)
    }) {
        let _ = answer.await;
    }
}
