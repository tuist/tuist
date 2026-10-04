//! The region that answered, over a real wire.
//!
//! Kura names its region on every REAPI response. The proxy has to pick it up
//! from answers and from not-found statuses alike: a miss is still a round trip
//! to a region.

use std::net::TcpListener as StdTcpListener;
use std::sync::Arc;

use bazel_remote_apis::build::bazel::remote::execution::v2 as reapi;
use reapi::action_cache_server::{ActionCache, ActionCacheServer};
use tonic::{Request, Response, Status};

use tuist_cas_plugin::reapi::{Remote, RemoteConfig};
use tuist_cas_plugin::token::TokenProvider;

struct NamedActionCache;

#[tonic::async_trait]
impl ActionCache for NamedActionCache {
    async fn get_action_result(
        &self,
        request: Request<reapi::GetActionResultRequest>,
    ) -> Result<Response<reapi::ActionResult>, Status> {
        let size = request
            .get_ref()
            .action_digest
            .as_ref()
            .map_or(0, |digest| digest.size_bytes);
        // One-byte keys miss.
        if size == 1 {
            let mut status = Status::not_found("miss");
            status
                .metadata_mut()
                .insert("x-kura-region", "ap-southeast".parse().unwrap());
            return Err(status);
        }
        let mut response = Response::new(reapi::ActionResult::default());
        response
            .metadata_mut()
            .insert("x-kura-region", "us-central".parse().unwrap());
        Ok(response)
    }

    async fn update_action_result(
        &self,
        _: Request<reapi::UpdateActionResultRequest>,
    ) -> Result<Response<reapi::ActionResult>, Status> {
        Err(Status::unimplemented("read-only"))
    }
}

fn spawn_server() -> std::net::SocketAddr {
    let listener = StdTcpListener::bind("127.0.0.1:0").expect("bind ephemeral port");
    listener
        .set_nonblocking(true)
        .expect("nonblocking for tokio adoption");
    let addr = listener.local_addr().expect("local addr");
    std::thread::spawn(move || {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("server runtime");
        rt.block_on(async move {
            let listener =
                tokio::net::TcpListener::from_std(listener).expect("adopt bound listener");
            let incoming = tonic::transport::server::TcpIncoming::from(listener);
            tonic::transport::Server::builder()
                .add_service(ActionCacheServer::new(NamedActionCache))
                .serve_with_incoming(incoming)
                .await
                .expect("serve");
        });
    });
    addr
}

fn remote_at(addr: std::net::SocketAddr) -> Arc<Remote> {
    Remote::new(
        RemoteConfig {
            grpc_url: format!("http://{addr}"),
            instance: "acme/app".into(),
        },
        TokenProvider::from_env(),
    )
}

#[test]
fn records_the_region_that_answered_hits_and_misses() {
    let remote = remote_at(spawn_server());
    assert_eq!(remote.served_by(), None, "nothing has answered yet");

    assert!(matches!(remote.get_action(b"m"), Ok(None)));
    assert_eq!(remote.served_by().as_deref(), Some("ap-southeast"));

    assert!(matches!(remote.get_action(b"hit"), Ok(Some(_))));
    assert_eq!(remote.served_by().as_deref(), Some("us-central"));
}
