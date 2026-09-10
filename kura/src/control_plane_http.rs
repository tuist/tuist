use std::time::Duration;

pub(crate) fn client_builder() -> reqwest::ClientBuilder {
    // Connection setup includes DNS. A remote region can spend more than one
    // second resolving Kubernetes search domains before starting TCP. Match
    // the managed auth client's connect budget, keeping the total request bounded.
    reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(3))
        .timeout(Duration::from_secs(5))
}

#[cfg(test)]
mod tests {
    use std::{net::SocketAddr, sync::Arc};

    use axum::{Router, http::StatusCode, routing::any};
    use reqwest::dns::{Addrs, Name, Resolve, Resolving};
    use tokio::net::TcpListener;

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
        let server = tokio::spawn(async move {
            axum::serve(
                listener,
                Router::new().route("/", any(|| async { StatusCode::NO_CONTENT })),
            )
            .await
            .unwrap();
        });
        let old_client = client_builder()
            .connect_timeout(Duration::from_secs(1))
            .no_proxy()
            .dns_resolver(Arc::new(DelayedResolver {
                address,
                delay: Duration::from_millis(1_200),
            }))
            .build()
            .unwrap();
        let old_error = old_client
            .get(format!("http://control-plane.test:{}/", address.port()))
            .send()
            .await
            .unwrap_err();
        assert!(old_error.is_timeout());

        for method in [reqwest::Method::GET, reqwest::Method::POST] {
            let client = client_builder()
                .no_proxy()
                .dns_resolver(Arc::new(DelayedResolver {
                    address,
                    delay: Duration::from_millis(1_200),
                }))
                .build()
                .unwrap();
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
        server.abort();
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
        assert_eq!(started.elapsed(), Duration::from_secs(3));
    }
}
