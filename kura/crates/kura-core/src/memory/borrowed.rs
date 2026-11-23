//! A response whose materialization borrowed ceiling headroom, with a bound on
//! how long it may hold that memory.
//!
//! A materialized response normally keeps its permit until the client has read
//! the body (`ResponseTransportGuard` rides on every chunk). That is why it may
//! only use floor-derived memory: nothing server-side bounds a slow reader, and
//! memory above the floor is unprotected. A borrowed response may use the
//! headroom because this type bounds it:
//!
//! - The body is handed to the transport one copied window at a time. hyper
//!   gives h2 each frame whole and then waits on flow control without polling
//!   the body again, so a whole-message frame would sit in h2's send buffer out
//!   of reach. Copies, because a slice of the encoded message shares its
//!   allocation and would keep all of it alive.
//! - The unsent rest, the encoder that still holds the message, and the
//!   permits live in shared state a timer task can take. At the deadline, or as
//!   soon as pressure leaves normal, the task drops them, which frees the
//!   memory even while hyper is parked on a closed window. The next poll fails
//!   the body, hyper resets the stream, and the client retries as it would
//!   after a shed. At most one window stays queued in h2.

use std::{
    pin::Pin,
    sync::{Arc, Mutex},
    task::{Context, Poll},
    time::Duration,
};

use axum::body::Body;
use bytes::{Buf, Bytes};
use http_body::{Body as HttpBody, Frame};
use tokio::sync::Notify;

use crate::constants::RESPONSE_STREAM_SEND_BUFFER_BYTES;

use super::{MemoryController, MemoryPermit, MemoryPressure};

/// How much of a borrowed response is handed to the transport at a time.
const BORROWED_RESPONSE_PIECE_BYTES: usize = RESPONSE_STREAM_SEND_BUFFER_BYTES;

struct Held {
    body: Option<Body>,
    pending: Bytes,
    _permits: Vec<MemoryPermit>,
}

struct Shared {
    held: Mutex<Option<Held>>,
    done: Notify,
}

impl Shared {
    fn release(&self) -> bool {
        let released = self.held.lock().expect("borrowed response lock").take();
        self.done.notify_one();
        released.is_some()
    }
}

/// Response extension for a materialization that borrowed ceiling headroom.
/// The HTTP layer turns it into the response body with [`Self::into_body`].
#[derive(Clone)]
pub struct BorrowedResponse {
    shared: Arc<Shared>,
}

impl BorrowedResponse {
    /// Takes the response's permits and starts the clock. Must be called on a
    /// Tokio runtime.
    pub fn new(memory: MemoryController, permits: Vec<MemoryPermit>, deadline: Duration) -> Self {
        let shared = Arc::new(Shared {
            held: Mutex::new(Some(Held {
                body: None,
                pending: Bytes::new(),
                _permits: permits,
            })),
            done: Notify::new(),
        });
        let watched = shared.clone();
        tokio::spawn(async move {
            let action = tokio::select! {
                _ = watched.done.notified() => return,
                _ = tokio::time::sleep(deadline) => "reapi_read_borrow_deadline_cancelled",
                _ = pressure_left_normal(&memory) => "reapi_read_borrow_pressure_cancelled",
            };
            if watched.release() {
                memory.inner.metrics.record_memory_action(action);
            }
        });
        Self { shared }
    }

    /// Moves the encoded body under the deadline. A body whose borrow was
    /// already cancelled fails on its first poll.
    pub fn into_body(self, body: Body) -> Body {
        if let Some(held) = self
            .shared
            .held
            .lock()
            .expect("borrowed response lock")
            .as_mut()
        {
            held.body = Some(body);
        }
        Body::new(BorrowedResponseBody {
            shared: self.shared,
        })
    }
}

async fn pressure_left_normal(memory: &MemoryController) {
    loop {
        let changed = memory.pressure_tier_changed();
        tokio::pin!(changed);
        changed.as_mut().enable();
        if memory.pressure() != MemoryPressure::Normal {
            return;
        }
        changed.await;
    }
}

struct BorrowedResponseBody {
    shared: Arc<Shared>,
}

impl HttpBody for BorrowedResponseBody {
    type Data = Bytes;
    type Error = axum::Error;

    fn poll_frame(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<Option<Result<Frame<Self::Data>, Self::Error>>> {
        let mut guard = self.shared.held.lock().expect("borrowed response lock");
        let Some(held) = guard.as_mut() else {
            return Poll::Ready(Some(Err(axum::Error::new(std::io::Error::other(
                "borrowed response memory was reclaimed before the client read it",
            )))));
        };
        loop {
            if !held.pending.is_empty() {
                let len = held.pending.len().min(BORROWED_RESPONSE_PIECE_BYTES);
                let piece = Bytes::copy_from_slice(&held.pending[..len]);
                held.pending.advance(len);
                if held.pending.is_empty() {
                    // An emptied slice still references the allocation.
                    held.pending = Bytes::new();
                }
                return Poll::Ready(Some(Ok(Frame::data(piece))));
            }
            let Some(body) = held.body.as_mut() else {
                return Poll::Ready(None);
            };
            match Pin::new(body).poll_frame(cx) {
                Poll::Ready(Some(Ok(frame))) => match frame.into_data() {
                    Ok(data) => held.pending = data,
                    Err(frame) => return Poll::Ready(Some(Ok(frame))),
                },
                Poll::Ready(None) => {
                    drop(guard);
                    self.shared.release();
                    return Poll::Ready(None);
                }
                other => return other,
            }
        }
    }
}

impl Drop for BorrowedResponseBody {
    fn drop(&mut self) {
        self.shared.release();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::metrics::Metrics;

    const MIB: u64 = 1024 * 1024;

    // 128 MiB of headroom with a 32 MiB floor budget: 32 MiB floor pool,
    // 96 MiB elastic, 48 MiB of it for reads, 16 MiB materialization limit.
    fn controller() -> MemoryController {
        MemoryController::with_anon_budget(
            Metrics::new("local".into(), "tenant".into()),
            512 * MIB,
            128 * MIB,
            256 * MIB,
            Some(32 * MIB),
        )
    }

    #[tokio::test]
    async fn read_borrowing_is_capped_at_half_the_headroom() {
        let memory = controller();
        let borrows: Vec<_> = (0..3)
            .map(|_| {
                memory
                    .try_borrow_response_materialization(8 * MIB as usize)
                    .expect("three 16 MiB borrows fit the 48 MiB read cap")
            })
            .collect();
        assert_eq!(memory.elastic_transient_reserved_bytes(), 48 * MIB);
        assert!(
            memory.try_borrow_response_materialization(1).is_err(),
            "reads must leave the other half of the headroom to writes"
        );
        drop(borrows);
        assert_eq!(memory.elastic_transient_reserved_bytes(), 0);
    }

    #[tokio::test]
    async fn pressure_leaving_normal_reclaims_an_unread_borrow() {
        let memory = controller();
        let permit = memory
            .try_borrow_response_materialization(8 * MIB as usize)
            .unwrap()
            .unwrap();
        let response =
            BorrowedResponse::new(memory.clone(), vec![permit], Duration::from_secs(3600));
        let _body = response.into_body(Body::from(vec![0_u8; 8 * MIB as usize]));
        assert_eq!(memory.elastic_transient_reserved_bytes(), 16 * MIB);

        memory.observe(200 * MIB);
        assert_eq!(memory.pressure(), MemoryPressure::Constrained);
        tokio::time::timeout(Duration::from_secs(5), async {
            while memory.elastic_transient_reserved_bytes() > 0 {
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .expect("leaving normal pressure must reclaim the borrow");
        assert!(
            memory.try_borrow_response_materialization(1).is_err(),
            "no new borrowing outside normal pressure"
        );
    }

    #[tokio::test]
    async fn borrowed_body_is_served_in_copied_windows() {
        use http_body_util::BodyExt;

        let memory = controller();
        let permit = memory
            .try_borrow_response_materialization(MIB as usize)
            .unwrap()
            .unwrap();
        let payload: Vec<u8> = (0..(MIB as usize + 17)).map(|i| i as u8).collect();
        let mut body =
            BorrowedResponse::new(memory.clone(), vec![permit], Duration::from_secs(3600))
                .into_body(Body::from(payload.clone()));
        let mut received = Vec::new();
        while let Some(frame) = body.frame().await {
            let data = frame.unwrap().into_data().unwrap();
            assert!(data.len() <= BORROWED_RESPONSE_PIECE_BYTES);
            received.extend_from_slice(&data);
        }
        assert_eq!(received, payload);
        assert_eq!(
            memory.elastic_transient_reserved_bytes(),
            0,
            "a finished body releases its borrow"
        );
    }
}
