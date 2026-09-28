//! Which Kura region and node answered this proxy's REAPI traffic, and when the
//! connection that carried it was established.
//!
//! A managed account's stable hostname (`<handle>.cache.tuist.dev`) is routed
//! by latency records the CLIENT's resolver picks, so a VPN or a corporate
//! resolver can send a build to a region far from where the machine is. Kura
//! names itself on every response (`x-kura-region`, `x-kura-node`); the proxy
//! records that next to each read and write in `cas_analytics.db`, and the
//! build report compares it with where the build came from.
//!
//! The connection time is there to rule out our own staleness. The proxy is a
//! long-lived daemon holding HTTP/2 connections across network changes, so a
//! far region can be one it resolved an hour ago on a network the machine has
//! since left. Hostname resolution and the TCP connect both happen in the
//! connector, so `connected_at` is also when the name was last resolved.

use std::future::Future;
use std::pin::Pin;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, RwLock};
use std::task::{Context, Poll};

use hyper_util::client::legacy::connect::HttpConnector;
use tonic::codegen::http::Uri;
use tonic::codegen::Service;
use tonic::metadata::MetadataMap;

pub const REGION_HEADER: &str = "x-kura-region";
pub const NODE_HEADER: &str = "x-kura-node";

/// Longest label accepted from a header. Region ids and pod names are short;
/// anything longer is not one of them and is not worth storing.
const MAX_LABEL_BYTES: usize = 64;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServedBy {
    pub region: Arc<str>,
    pub node: Arc<str>,
    /// Unix milliseconds the connection that answered was established, or 0
    /// when it is not known.
    pub connected_at_ms: u64,
}

#[derive(Default)]
pub struct ServedByCell {
    labels: RwLock<Option<(Arc<str>, Arc<str>)>>,
    connected_at_ms: AtomicU64,
}

impl ServedByCell {
    /// Records who answered a call. A response from a Kura that predates the
    /// headers leaves the cell as it was.
    pub fn observe(&self, metadata: &MetadataMap) {
        let Some(region) = label(metadata, REGION_HEADER) else {
            return;
        };
        let node = label(metadata, NODE_HEADER).unwrap_or_default();
        if let Some((current_region, current_node)) = self.labels.read().unwrap().as_ref() {
            if **current_region == *region && **current_node == *node {
                return;
            }
        }
        *self.labels.write().unwrap() = Some((region.into(), node.into()));
    }

    /// A new connection is up. Whoever answered on the previous one says
    /// nothing about who answers on this one, so the labels are forgotten
    /// until its first response.
    pub fn connected(&self, at_ms: u64) {
        self.connected_at_ms.store(at_ms, Ordering::Relaxed);
        *self.labels.write().unwrap() = None;
    }

    pub fn current(&self) -> Option<ServedBy> {
        let (region, node) = self.labels.read().unwrap().clone()?;
        Some(ServedBy {
            region,
            node,
            connected_at_ms: self.connected_at_ms.load(Ordering::Relaxed),
        })
    }
}

fn label(metadata: &MetadataMap, name: &str) -> Option<String> {
    let value = metadata.get(name)?.to_str().ok()?.trim();
    let valid = !value.is_empty()
        && value.len() <= MAX_LABEL_BYTES
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.'));
    valid.then(|| value.to_owned())
}

/// The connector tonic would build for the endpoint, stamping the cell each
/// time it opens a connection. TLS is layered on top by tonic.
#[derive(Clone)]
pub struct StampingConnector {
    inner: HttpConnector,
    cell: Arc<ServedByCell>,
}

impl StampingConnector {
    pub fn new(cell: Arc<ServedByCell>, connect_timeout: std::time::Duration) -> Self {
        let mut inner = HttpConnector::new();
        // Same settings `Endpoint::connect_lazy` gives its own connector.
        inner.enforce_http(false);
        inner.set_nodelay(true);
        inner.set_connect_timeout(Some(connect_timeout));
        Self { inner, cell }
    }
}

type ConnectFuture = Pin<
    Box<
        dyn Future<Output = Result<<HttpConnector as Service<Uri>>::Response, ConnectError>> + Send,
    >,
>;
type ConnectError = <HttpConnector as Service<Uri>>::Error;

impl Service<Uri> for StampingConnector {
    type Response = <HttpConnector as Service<Uri>>::Response;
    type Error = ConnectError;
    type Future = ConnectFuture;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, uri: Uri) -> Self::Future {
        let connecting = self.inner.call(uri);
        let cell = self.cell.clone();
        Box::pin(async move {
            let stream = connecting.await?;
            cell.connected(crate::reapi::now_ms());
            Ok(stream)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn metadata(headers: &[(&'static str, &'static str)]) -> MetadataMap {
        let mut metadata = MetadataMap::new();
        for (name, value) in headers {
            metadata.insert(*name, value.parse().unwrap());
        }
        metadata
    }

    #[test]
    fn records_the_region_and_node_that_answered() {
        let cell = ServedByCell::default();
        cell.connected(1_000);
        cell.observe(&metadata(&[
            (REGION_HEADER, "us-central"),
            (NODE_HEADER, "acme-us-central-0"),
        ]));

        assert_eq!(
            cell.current(),
            Some(ServedBy {
                region: "us-central".into(),
                node: "acme-us-central-0".into(),
                connected_at_ms: 1_000,
            })
        );
    }

    #[test]
    fn a_kura_without_the_headers_leaves_it_unknown() {
        let cell = ServedByCell::default();
        cell.observe(&metadata(&[]));
        assert_eq!(cell.current(), None);
    }

    #[test]
    fn a_new_connection_forgets_who_answered_the_last_one() {
        let cell = ServedByCell::default();
        cell.observe(&metadata(&[(REGION_HEADER, "us-central")]));
        cell.connected(2_000);
        assert_eq!(cell.current(), None);

        cell.observe(&metadata(&[(REGION_HEADER, "ap-southeast")]));
        let current = cell.current().unwrap();
        assert_eq!(&*current.region, "ap-southeast");
        assert_eq!(&*current.node, "");
        assert_eq!(current.connected_at_ms, 2_000);
    }

    #[test]
    fn refuses_values_that_are_not_labels() {
        let cell = ServedByCell::default();
        cell.observe(&metadata(&[(REGION_HEADER, "us central; drop")]));
        assert_eq!(cell.current(), None);

        let long = "a".repeat(MAX_LABEL_BYTES + 1);
        let mut map = MetadataMap::new();
        map.insert(REGION_HEADER, long.parse().unwrap());
        cell.observe(&map);
        assert_eq!(cell.current(), None);
    }
}
