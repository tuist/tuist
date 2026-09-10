use std::time::Duration;

const CONNECT_TIMEOUT_SECS: u64 = 3;
const REQUEST_TIMEOUT_SECS: u64 = 5;
const _: () = assert!(CONNECT_TIMEOUT_SECS < REQUEST_TIMEOUT_SECS);

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
