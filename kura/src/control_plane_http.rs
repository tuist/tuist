use std::time::Duration;

use tracing::warn;

pub(crate) const CONNECT_TIMEOUT_SECS: u64 = 3;
pub(crate) const REQUEST_TIMEOUT_SECS: u64 = 5;
const _: () = assert!(CONNECT_TIMEOUT_SECS < REQUEST_TIMEOUT_SECS);

/// The client the analytics and Bazel test-artifact pipelines deliver on.
///
/// They both read their request timeout from `AnalyticsConfig` and both post
/// to the Tuist server, so they get the same connect budget as everything else
/// here. Connect spans DNS, and a node in a region away from the control plane
/// pays a WAN round trip per lookup before the handshake, so the 500ms these
/// used to hardcode could not be met from outside the control plane's own
/// region: a remote node failed every batch at connect while its control-plane
/// client, pointed at the same host, kept succeeding.
pub(crate) fn analytics_client_builder(request_timeout_ms: u64) -> reqwest::ClientBuilder {
    reqwest::Client::builder()
        .connect_timeout(Duration::from_millis(analytics_connect_timeout_ms(
            request_timeout_ms,
        )))
        .timeout(Duration::from_millis(request_timeout_ms))
}

/// The connect budget above, lowered to a request timeout set below it.
fn analytics_connect_timeout_ms(request_timeout_ms: u64) -> u64 {
    let connect_timeout_ms = CONNECT_TIMEOUT_SECS * 1_000;
    if connect_timeout_ms < request_timeout_ms {
        return connect_timeout_ms;
    }

    // reqwest's request timeout spans the connect, so a budget at or above it
    // can never be reached and the handshake is given up on early.
    warn!(
        "the analytics request timeout ({request_timeout_ms}ms) is not above the {connect_timeout_ms}ms connect budget, which it spans; using {request_timeout_ms}ms for the connect."
    );
    request_timeout_ms
}

pub(crate) fn client_builder() -> reqwest::ClientBuilder {
    // Connection setup includes DNS. A remote region can spend more than one
    // second resolving Kubernetes search domains before starting TCP. Match
    // the managed auth client's connect budget, keeping the total request bounded.
    reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(CONNECT_TIMEOUT_SECS))
        .timeout(Duration::from_secs(REQUEST_TIMEOUT_SECS))
}

#[cfg(test)]
mod tests {
    use std::{net::SocketAddr, sync::Arc};

    use axum::{Router, http::StatusCode, routing::any};
    use reqwest::dns::{Addrs, Name, Resolve, Resolving};
    use tokio::{net::TcpListener, sync::oneshot};

    use super::*;

    struct DelayedResolver {
        address: SocketAddr,
        delay: Duration,
    }

    impl Resolve for DelayedResolver {
        fn resolve(&self, _: Name) -> Resolving {
            let address = self.address;
            let delay = self.delay;
            Box::pin(async move {
                tokio::time::sleep(delay).await;
                Ok(Box::new(std::iter::once(address)) as Addrs)
            })
        }
    }

    #[tokio::test]
    async fn control_plane_requests_allow_dns_to_take_more_than_one_second() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let (shutdown, shutdown_received) = oneshot::channel();
        let server = tokio::spawn(async move {
            axum::serve(
                listener,
                Router::new().route("/", any(|| async { StatusCode::NO_CONTENT })),
            )
            .with_graceful_shutdown(async { shutdown_received.await.unwrap() })
            .await
        });
        let client = client_builder()
            .no_proxy()
            .dns_resolver(Arc::new(DelayedResolver {
                address,
                delay: Duration::from_millis(1_200),
            }))
            .build()
            .unwrap();
        for method in [reqwest::Method::GET, reqwest::Method::POST] {
            let response = client
                .request(
                    method,
                    format!("http://control-plane.test:{}/", address.port()),
                )
                .send()
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::NO_CONTENT);
        }
        shutdown.send(()).unwrap();
        server.await.unwrap().unwrap();
    }

    #[test]
    fn the_analytics_budget_is_the_control_plane_one() {
        assert_eq!(
            analytics_connect_timeout_ms(5_000),
            CONNECT_TIMEOUT_SECS * 1_000,
            "analytics and Bazel test-artifact delivery must get the same connect \
             budget as everything else here; a tighter one cannot be met from a \
             region away from the control plane, where connect spends a WAN round \
             trip per DNS lookup before the handshake"
        );
    }

    #[test]
    fn the_analytics_budget_stays_within_a_shorter_request_timeout() {
        // reqwest's request timeout spans the connect, so an operator who sets
        // a request timeout below the connect budget would otherwise get a
        // budget that can never be reached.
        let budget = CONNECT_TIMEOUT_SECS * 1_000;
        assert_eq!(analytics_connect_timeout_ms(1_000), 1_000);
        assert_eq!(analytics_connect_timeout_ms(budget - 1), budget - 1);
        assert_eq!(analytics_connect_timeout_ms(budget + 1), budget);
    }

    /// The analytics pipelines used to hardcode 500ms, which this same delay
    /// defeats — that is what a remote node hit in production.
    #[tokio::test]
    async fn analytics_delivery_allows_dns_to_take_more_than_half_a_second() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let (shutdown, shutdown_received) = oneshot::channel();
        let server = tokio::spawn(async move {
            axum::serve(
                listener,
                Router::new().route("/", any(|| async { StatusCode::NO_CONTENT })),
            )
            .with_graceful_shutdown(async { shutdown_received.await.unwrap() })
            .await
        });
        let client = analytics_client_builder(5_000)
            .no_proxy()
            .dns_resolver(Arc::new(DelayedResolver {
                address,
                delay: Duration::from_millis(1_200),
            }))
            .build()
            .unwrap();
        let response = client
            .post(format!("http://control-plane.test:{}/", address.port()))
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::NO_CONTENT);
        shutdown.send(()).unwrap();
        server.await.unwrap().unwrap();
    }

    #[tokio::test(start_paused = true)]
    async fn stalled_dns_still_exhausts_the_connect_budget() {
        let client = client_builder()
            .no_proxy()
            .dns_resolver(Arc::new(DelayedResolver {
                address: "127.0.0.1:1".parse().unwrap(),
                delay: Duration::from_secs(60),
            }))
            .build()
            .unwrap();
        let started = tokio::time::Instant::now();
        let error = client
            .get("http://control-plane.test/")
            .send()
            .await
            .unwrap_err();
        assert!(error.is_timeout());
        assert!(started.elapsed() >= Duration::from_secs(CONNECT_TIMEOUT_SECS));
        assert!(started.elapsed() < Duration::from_secs(REQUEST_TIMEOUT_SECS));
    }
}
