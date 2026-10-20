//! Wire-compatible subset of REAPI v2 and google.bytestream.
//! Field numbers match the protocol subsets in cli/Sources/TuistREAPI.
use prost::Message;

#[derive(Clone, PartialEq, Eq, Hash, Message)]
pub(crate) struct Digest {
    #[prost(string, tag = "1")]
    pub hash: String,
    #[prost(int64, tag = "2")]
    pub size_bytes: i64,
}
#[derive(Clone, PartialEq, Message)]
pub(crate) struct Command {
    #[prost(string, repeated, tag = "1")]
    pub arguments: Vec<String>,
    #[prost(string, repeated, tag = "7")]
    pub output_paths: Vec<String>,
}
#[derive(Clone, PartialEq, Message)]
pub(crate) struct Action {
    #[prost(message, optional, tag = "1")]
    pub command_digest: Option<Digest>,
    #[prost(message, optional, tag = "2")]
    pub input_root_digest: Option<Digest>,
}
#[derive(Clone, PartialEq, Message)]
pub(crate) struct OutputFile {
    #[prost(string, tag = "1")]
    pub path: String,
    #[prost(message, optional, tag = "2")]
    pub digest: Option<Digest>,
}
#[derive(Clone, PartialEq, Message)]
pub(crate) struct ActionResult {
    #[prost(message, repeated, tag = "2")]
    pub output_files: Vec<OutputFile>,
    #[prost(int32, tag = "4")]
    pub exit_code: i32,
}
#[derive(Clone, PartialEq, Message)]
pub(crate) struct GetActionResultRequest {
    #[prost(string, tag = "1")]
    pub instance_name: String,
    #[prost(message, optional, tag = "2")]
    pub action_digest: Option<Digest>,
    #[prost(int32, tag = "6")]
    pub digest_function: i32,
}
#[derive(Clone, PartialEq, Message)]
pub(crate) struct UpdateActionResultRequest {
    #[prost(string, tag = "1")]
    pub instance_name: String,
    #[prost(message, optional, tag = "2")]
    pub action_digest: Option<Digest>,
    #[prost(message, optional, tag = "3")]
    pub action_result: Option<ActionResult>,
    #[prost(int32, tag = "5")]
    pub digest_function: i32,
}
#[derive(Clone, PartialEq, Message)]
pub(crate) struct FindMissingBlobsRequest {
    #[prost(string, tag = "1")]
    pub instance_name: String,
    #[prost(message, repeated, tag = "2")]
    pub blob_digests: Vec<Digest>,
    #[prost(int32, tag = "3")]
    pub digest_function: i32,
}
#[derive(Clone, PartialEq, Message)]
pub(crate) struct FindMissingBlobsResponse {
    #[prost(message, repeated, tag = "2")]
    pub missing_blob_digests: Vec<Digest>,
}
#[derive(Clone, PartialEq, Message)]
pub(crate) struct GetCapabilitiesRequest {
    #[prost(string, tag = "1")]
    pub instance_name: String,
}
#[derive(Clone, PartialEq, Message)]
pub(crate) struct ServerCapabilities {
    #[prost(message, optional, tag = "1")]
    pub cache_capabilities: Option<CacheCapabilities>,
}
#[derive(Clone, PartialEq, Message)]
pub(crate) struct CacheCapabilities {
    #[prost(int32, repeated, tag = "1")]
    pub digest_functions: Vec<i32>,
    #[prost(message, optional, tag = "2")]
    pub action_cache_update_capabilities: Option<ActionCacheUpdateCapabilities>,
}
#[derive(Clone, PartialEq, Message)]
pub(crate) struct ActionCacheUpdateCapabilities {
    #[prost(bool, tag = "1")]
    pub update_enabled: bool,
}
#[derive(Clone, PartialEq, Message)]
pub(crate) struct ReadRequest {
    #[prost(string, tag = "1")]
    pub resource_name: String,
    #[prost(int64, tag = "2")]
    pub read_offset: i64,
    #[prost(int64, tag = "3")]
    pub read_limit: i64,
}
#[derive(Clone, PartialEq, Message)]
pub(crate) struct ReadResponse {
    #[prost(bytes = "vec", tag = "10")]
    pub data: Vec<u8>,
}
#[derive(Clone, PartialEq, Message)]
pub(crate) struct WriteRequest {
    #[prost(string, tag = "1")]
    pub resource_name: String,
    #[prost(int64, tag = "2")]
    pub write_offset: i64,
    #[prost(bool, tag = "3")]
    pub finish_write: bool,
    #[prost(bytes = "vec", tag = "10")]
    pub data: Vec<u8>,
}
#[derive(Clone, PartialEq, Message)]
pub(crate) struct WriteResponse {
    #[prost(int64, tag = "1")]
    pub committed_size: i64,
}
