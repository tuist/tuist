//! Keeps one of the core's live sockets (`tuist_app_core::Live`) open for a
//! view: the inbox's, or the person's AI subscriptions'. The core decides when
//! to connect, heartbeat and reconnect, and how often the view may reload
//! (`refresh_ms`); the socket's own thread and the background executor keep
//! the network off the UI thread.
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::time::{Duration, Instant};

use gpui::{Context, Task};
use tuist_app_core::{Live, Socket};
use tuist_session::Session;
use url::Url;

use super::socket::WebSocket;

/// How often frames are read; the socket's thread buffers them meanwhile.
const READ: Duration = Duration::from_millis(250);

fn lock(state: &Mutex<(Live, WebSocket)>) -> MutexGuard<'_, (Live, WebSocket)> {
    state.lock().unwrap_or_else(PoisonError::into_inner)
}

/// Follows socket `id` in `account` until the returned task is dropped, which
/// closes it. `refresh` reloads the view when the server says it changed; it
/// returns false when it can't reload now, and is asked again on the next read.
pub(super) fn follow<T: 'static>(
    session: Arc<Session>,
    account: String,
    id: &'static str,
    cx: &mut Context<T>,
    refresh: impl Fn(&mut T, &mut Context<T>) -> bool + 'static,
) -> Task<()> {
    let state = Arc::new(Mutex::new((Live::default(), WebSocket::default())));
    cx.spawn(async move |this, cx| {
        let mut refreshed: Option<Instant> = None;
        let mut pending = false;
        loop {
            let delay = lock(&state).0.wait(id);
            cx.background_executor()
                .timer(Duration::from_millis(delay))
                .await;
            let (shared, session, handle) = (state.clone(), session.clone(), account.clone());
            let plan = cx
                .background_executor()
                .spawn(async move {
                    let token = session
                        .access_token()
                        .map_err(|_| "Sign in again to continue")?;
                    let mut guard = lock(&shared);
                    let (live, socket) = &mut *guard;
                    let plan = live.connect(id, session.server(), &handle, id, &token)?;
                    let url = Url::parse(plan["url"].as_str().unwrap_or_default())
                        .map_err(|_| "Invalid server")?;
                    let protocols: Vec<String> = plan["protocols"]
                        .as_array()
                        .into_iter()
                        .flatten()
                        .filter_map(|p| p.as_str().map(str::to_owned))
                        .collect();
                    socket.open(&url, &protocols)?;
                    socket.send(plan["join"].as_str().unwrap_or_default())?;
                    Ok::<_, &'static str>(plan)
                })
                .await;
            let Ok(plan) = plan else { continue };
            let tick = Duration::from_millis(plan["tick_ms"].as_u64().unwrap_or(30_000));
            let spacing = Duration::from_millis(plan["refresh_ms"].as_u64().unwrap_or(0));
            let mut ticked = Instant::now();
            loop {
                cx.background_executor().timer(READ).await;
                let (shared, account) = (state.clone(), account.clone());
                let (changed, reconnect) = cx
                    .background_executor()
                    .spawn(async move {
                        let mut guard = lock(&shared);
                        let (live, socket) = &mut *guard;
                        let Ok((frames, closed)) = socket.read() else {
                            return (false, true);
                        };
                        let mut changed = false;
                        for frame in frames {
                            let Ok(out) = live.receive(id, &account, id, &frame) else {
                                continue;
                            };
                            for reply in out["replies"].as_array().into_iter().flatten() {
                                let _ = socket.send(reply.as_str().unwrap_or_default());
                            }
                            changed |= out["refresh"] == true;
                            if out["reconnect"] == true {
                                return (changed, true);
                            }
                        }
                        if ticked.elapsed() >= tick {
                            let out = live.tick(id);
                            for frame in out["send"].as_array().into_iter().flatten() {
                                if socket.send(frame.as_str().unwrap_or_default()).is_err() {
                                    return (changed, true);
                                }
                            }
                            if out["reconnect"] == true {
                                return (changed, true);
                            }
                        }
                        (changed, closed)
                    })
                    .await;
                if ticked.elapsed() >= tick {
                    ticked = Instant::now();
                }
                pending |= changed;
                if pending && refreshed.is_none_or(|at| at.elapsed() >= spacing) {
                    let reloaded = this
                        .update(cx, |this, cx| refresh(this, cx))
                        .unwrap_or(false);
                    if reloaded {
                        pending = false;
                        refreshed = Some(Instant::now());
                    }
                }
                if reconnect {
                    lock(&state).1.close();
                    break;
                }
            }
        }
    })
}
