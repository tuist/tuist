//! Names the region and node that answered each REAPI call.
//!
//! A managed account's stable hostname is routed by the client's DNS
//! resolver, so which region a client reaches is decided by its network (a
//! VPN, a corporate resolver), not by the control plane. The CAS proxy records
//! these headers next to the reads and writes it makes, which is how a build
//! report says which region served it rather than support inferring it from
//! read counters. Both are sent as initial metadata, so trailers-only error
//! responses carry them too.

use std::{net::IpAddr, sync::Arc};

use axum::{
    http::{HeaderName, HeaderValue},
    response::Response,
};

pub(crate) const REGION_HEADER: HeaderName = HeaderName::from_static("x-kura-region");
pub(crate) const NODE_HEADER: HeaderName = HeaderName::from_static("x-kura-node");

#[derive(Clone)]
pub(crate) struct ServedBy {
    headers: Arc<[(HeaderName, HeaderValue)]>,
}

impl ServedBy {
    pub(crate) fn new(region: &str, node_url: &str) -> Self {
        let headers = [
            (REGION_HEADER, Some(region.to_owned())),
            (NODE_HEADER, node_name(node_url)),
        ]
        .into_iter()
        .filter_map(|(name, value)| {
            let value = HeaderValue::from_str(&value?).ok()?;
            (!value.is_empty()).then_some((name, value))
        })
        .collect();
        Self { headers }
    }

    pub(crate) fn apply(&self, response: &mut Response) {
        let headers = response.headers_mut();
        for (name, value) in self.headers.iter() {
            headers.insert(name.clone(), value.clone());
        }
    }
}

/// The node's name: the first DNS label of its node URL, which is the pod name
/// in every managed deployment (`<pod>.<headless service>...`). An address is
/// not a name, and would say where the node sits on the network rather than
/// which one it is, so it is left out.
pub(crate) fn node_name(node_url: &str) -> Option<String> {
    let url = reqwest::Url::parse(node_url).ok()?;
    let host = url
        .host_str()?
        .trim_start_matches('[')
        .trim_end_matches(']');
    if host.parse::<IpAddr>().is_ok() {
        return None;
    }
    host.split('.')
        .next()
        .filter(|label| !label.is_empty())
        .map(str::to_owned)
}

#[cfg(test)]
mod tests {
    use axum::body::Body;

    use super::*;

    #[test]
    fn names_the_node_by_the_first_label_of_its_url() {
        assert_eq!(
            node_name("http://acme-us-central-0.kura-headless.kura.svc.cluster.local:7443")
                .as_deref(),
            Some("acme-us-central-0")
        );
        assert_eq!(
            node_name("http://kura-us.kura.internal:7443").as_deref(),
            Some("kura-us")
        );
    }

    #[test]
    fn does_not_name_a_node_by_its_address() {
        assert_eq!(node_name("http://10.0.0.7:7443"), None);
        assert_eq!(node_name("http://[fd00::7]:7443"), None);
        assert_eq!(node_name("not a url"), None);
    }

    #[test]
    fn stamps_region_and_node_on_a_response() {
        let served_by = ServedBy::new("us-central", "http://acme-us-central-0.svc:7443");
        let mut response = Response::new(Body::empty());
        served_by.apply(&mut response);

        assert_eq!(response.headers()[&REGION_HEADER], "us-central");
        assert_eq!(response.headers()[&NODE_HEADER], "acme-us-central-0");
    }

    #[test]
    fn omits_what_it_cannot_send_as_a_header() {
        let served_by = ServedBy::new("", "http://10.0.0.7:7443");
        let mut response = Response::new(Body::empty());
        served_by.apply(&mut response);

        assert!(response.headers().get(&REGION_HEADER).is_none());
        assert!(response.headers().get(&NODE_HEADER).is_none());
    }
}
