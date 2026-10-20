//! `Remote::reachable` against a real gRPC server.
//!
//! The proxy leaves its current endpoint at once when this check fails, so
//! anything the server itself sends back has to count as an answer, whatever
//! its status: an endpoint that answers `INTERNAL` is serving and must go
//! through the endpoint confirmation instead. Only failures where no server
//! answered count as unreachable.

use std::net::TcpListener as StdTcpListener;
use std::time::Duration;

use bazel_remote_apis::build::bazel::remote::execution::v2 as reapi;
use reapi::capabilities_server::{Capabilities, CapabilitiesServer};
use tonic::{Code, Request, Response, Status};

use tuist_cas_plugin::reapi::{Remote, RemoteConfig};
use tuist_cas_plugin::token::TokenProvider;

struct AnsweringCapabilities {
    code: Code,
}

#[tonic::async_trait]
impl Capabilities for AnsweringCapabilities {
    async fn get_capabilities(
        &self,
        _: Request<reapi::GetCapabilitiesRequest>,
    ) -> Result<Response<reapi::ServerCapabilities>, Status> {
        match self.code {
            Code::Ok => Ok(Response::new(reapi::ServerCapabilities::default())),
            code => Err(Status::new(code, "answered by the server")),
        }
    }
}

fn spawn_server(code: Code) -> std::net::SocketAddr {
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
                .add_service(CapabilitiesServer::new(AnsweringCapabilities { code }))
                .serve_with_incoming(incoming)
                .await
                .expect("serve");
        });
    });
    addr
}

fn remote_at(url: String) -> std::sync::Arc<Remote> {
    Remote::new(
        RemoteConfig {
            grpc_url: url,
            instance: "test".into(),
        },
        TokenProvider::from_env(),
    )
}

#[test]
fn every_status_the_server_sends_back_counts_as_reachable() {
    for code in [
        Code::Ok,
        Code::PermissionDenied,
        Code::Unimplemented,
        Code::ResourceExhausted,
        Code::Unavailable,
        Code::Unknown,
        Code::DeadlineExceeded,
        Code::Cancelled,
        Code::Internal,
    ] {
        let remote = remote_at(format!("http://{}", spawn_server(code)));

        assert!(
            remote.reachable(),
            "a server that answers {code:?} is reachable"
        );
    }
}

#[test]
fn a_refused_connection_is_unreachable() {
    let addr = StdTcpListener::bind("127.0.0.1:0")
        .expect("bind ephemeral port")
        .local_addr()
        .expect("local addr");

    assert!(!remote_at(format!("http://{addr}")).reachable());
}

#[test]
fn a_server_that_never_answers_is_unreachable() {
    let listener = StdTcpListener::bind("127.0.0.1:0").expect("bind ephemeral port");
    let addr = listener.local_addr().expect("local addr");
    std::thread::spawn(move || {
        let mut held = Vec::new();
        for stream in listener.incoming() {
            held.push(stream);
        }
    });

    let started = std::time::Instant::now();
    assert!(!remote_at(format!("http://{addr}")).reachable());
    assert!(
        started.elapsed() < Duration::from_secs(30),
        "the check is bounded by its own timeout (took {:?})",
        started.elapsed()
    );
}
