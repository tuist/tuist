//! Loopback-only fault gate for Kura's compiler ShellSpec tests.
//! All storage and reconstruction stay in real Kura. ShellSpec controls the
//! interruption or namespace deletion while requests are held at this gate.

use bazel_remote_apis::build::bazel::remote::execution::v2 as api;
use std::{
    collections::HashSet,
    fs::{self, OpenOptions},
    io::Write,
    path::PathBuf,
    pin::Pin,
    sync::{Arc, Mutex},
    time::Duration,
};
use tonic::{transport::Channel, Request, Response, Status};

#[derive(Clone)]
struct Gate {
    upstream: Channel,
    directory: PathBuf,
    chunks: Arc<Mutex<HashSet<String>>>,
    log: Arc<Mutex<std::fs::File>>,
}

impl Gate {
    fn mode(&self) -> String {
        fs::read_to_string(self.directory.join("mode"))
            .unwrap_or_default()
            .trim()
            .to_owned()
    }

    fn event(&self, name: &str) {
        writeln!(self.log.lock().unwrap(), "{name}").unwrap();
    }

    fn storage(
        &self,
    ) -> api::content_addressable_storage_client::ContentAddressableStorageClient<Channel> {
        api::content_addressable_storage_client::ContentAddressableStorageClient::new(
            self.upstream.clone(),
        )
        .max_decoding_message_size(64 * 1024 * 1024)
        .max_encoding_message_size(64 * 1024 * 1024)
    }
}

#[tonic::async_trait]
impl api::capabilities_server::Capabilities for Gate {
    async fn get_capabilities(
        &self,
        request: Request<api::GetCapabilitiesRequest>,
    ) -> Result<Response<api::ServerCapabilities>, Status> {
        api::capabilities_client::CapabilitiesClient::new(self.upstream.clone())
            .get_capabilities(request)
            .await
    }
}

#[tonic::async_trait]
impl api::action_cache_server::ActionCache for Gate {
    async fn get_action_result(
        &self,
        request: Request<api::GetActionResultRequest>,
    ) -> Result<Response<api::ActionResult>, Status> {
        let response = api::action_cache_client::ActionCacheClient::new(self.upstream.clone())
            .max_decoding_message_size(64 * 1024 * 1024)
            .get_action_result(request)
            .await;
        if response.is_ok() {
            self.event("action-hit");
        }
        response
    }

    async fn update_action_result(
        &self,
        request: Request<api::UpdateActionResultRequest>,
    ) -> Result<Response<api::ActionResult>, Status> {
        self.event("action-put");
        api::action_cache_client::ActionCacheClient::new(self.upstream.clone())
            .update_action_result(request)
            .await
    }
}

#[tonic::async_trait]
impl api::content_addressable_storage_server::ContentAddressableStorage for Gate {
    async fn find_missing_blobs(
        &self,
        request: Request<api::FindMissingBlobsRequest>,
    ) -> Result<Response<api::FindMissingBlobsResponse>, Status> {
        self.storage().find_missing_blobs(request).await
    }

    async fn batch_update_blobs(
        &self,
        mut request: Request<api::BatchUpdateBlobsRequest>,
    ) -> Result<Response<api::BatchUpdateBlobsResponse>, Status> {
        if self.mode() == "interrupt-upload" {
            // Commit one chunk, then lose the response and the remaining chunks.
            // The publisher must leave its durable spool record, not an action.
            request.get_mut().requests.truncate(1);
            self.storage().batch_update_blobs(request).await?;
            self.event("interrupted-upload");
            return Err(Status::aborted("test interrupted the upload"));
        }
        self.storage().batch_update_blobs(request).await
    }

    async fn batch_read_blobs(
        &self,
        request: Request<api::BatchReadBlobsRequest>,
    ) -> Result<Response<api::BatchReadBlobsResponse>, Status> {
        let chunk_read = {
            let chunks = self.chunks.lock().unwrap();
            request
                .get_ref()
                .digests
                .iter()
                .any(|digest| chunks.contains(&digest.hash))
        };
        if chunk_read && self.mode() == "hold-chunks" {
            self.event("chunk-read-held");
            fs::write(self.directory.join("chunk-read-held"), b"").unwrap();
            tokio::time::timeout(Duration::from_secs(45), async {
                while !self.directory.join("release").exists() {
                    tokio::time::sleep(Duration::from_millis(10)).await;
                }
            })
            .await
            .map_err(|_| Status::deadline_exceeded("test did not release chunk read"))?;
        }
        let response = self.storage().batch_read_blobs(request).await?;
        if response
            .get_ref()
            .responses
            .iter()
            .any(|entry| entry.status.as_ref().is_some_and(|status| status.code == 5))
        {
            self.event(if chunk_read {
                "chunk-missing"
            } else {
                "whole-missing"
            });
        }
        Ok(response)
    }

    async fn split_blob(
        &self,
        request: Request<api::SplitBlobRequest>,
    ) -> Result<Response<api::SplitBlobResponse>, Status> {
        let response = self.storage().split_blob(request).await?;
        self.chunks.lock().unwrap().extend(
            response
                .get_ref()
                .chunk_digests
                .iter()
                .map(|digest| digest.hash.clone()),
        );
        self.event("recipe-returned");
        Ok(response)
    }

    async fn splice_blob(
        &self,
        request: Request<api::SpliceBlobRequest>,
    ) -> Result<Response<api::SpliceBlobResponse>, Status> {
        let response = self.storage().splice_blob(request).await?;
        self.event("splice-completed");
        Ok(response)
    }

    type GetTreeStream = Pin<
        Box<
            dyn tonic::codegen::tokio_stream::Stream<Item = Result<api::GetTreeResponse, Status>>
                + Send,
        >,
    >;
    async fn get_tree(
        &self,
        request: Request<api::GetTreeRequest>,
    ) -> Result<Response<Self::GetTreeStream>, Status> {
        let response = self.storage().get_tree(request).await?;
        Ok(Response::new(Box::pin(response.into_inner())))
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args.len() != 2 {
        return Err(
            "usage: chunking_fault_gate http://127.0.0.1:PORT EXISTING_CONTROL_DIRECTORY".into(),
        );
    }
    let port = args[0]
        .strip_prefix("http://127.0.0.1:")
        .ok_or("upstream must be loopback")?
        .parse::<u16>()?;
    if port == 0 {
        return Err("upstream port must not be zero".into());
    }
    let directory = PathBuf::from(&args[1]).canonicalize()?;
    tokio::runtime::Runtime::new()?.block_on(async {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
        let address = listener.local_addr()?;
        let gate = Gate {
            upstream: Channel::from_shared(args[0].clone())?.connect().await?,
            log: Arc::new(Mutex::new(
                OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(directory.join("events"))?,
            )),
            directory: directory.clone(),
            chunks: Arc::new(Mutex::new(HashSet::new())),
        };
        fs::write(directory.join("address"), format!("http://{address}"))?;
        tonic::transport::Server::builder()
            .add_service(api::capabilities_server::CapabilitiesServer::new(
                gate.clone(),
            ))
            .add_service(
                api::action_cache_server::ActionCacheServer::new(gate.clone())
                    .max_decoding_message_size(64 * 1024 * 1024)
                    .max_encoding_message_size(64 * 1024 * 1024),
            )
            .add_service(
                api::content_addressable_storage_server::ContentAddressableStorageServer::new(gate)
                    .max_decoding_message_size(64 * 1024 * 1024)
                    .max_encoding_message_size(64 * 1024 * 1024),
            )
            .serve_with_incoming(tonic::transport::server::TcpIncoming::from(listener))
            .await?;
        Ok(())
    })
}
