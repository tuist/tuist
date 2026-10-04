//! Names the region that answered each REAPI call.
//!
//! A managed account's stable hostname is routed by the client's DNS
//! resolver, so which region a client reaches is decided by its network (a
//! VPN, a corporate resolver), not by the control plane. The CAS proxy records
//! this header next to the reads and writes it makes, which is how a build
//! says which region served it. It is sent as initial metadata, so
//! trailers-only error responses carry it too.

use axum::{
    http::{HeaderName, HeaderValue},
    response::Response,
};

pub(crate) const REGION_HEADER: HeaderName = HeaderName::from_static("x-kura-region");

#[derive(Clone)]
pub(crate) struct ServedBy {
    region: Option<HeaderValue>,
}

impl ServedBy {
    pub(crate) fn new(region: &str) -> Self {
        let region = HeaderValue::from_str(region)
            .ok()
            .filter(|value| !value.is_empty());
        Self { region }
    }

    pub(crate) fn apply(&self, response: &mut Response) {
        if let Some(region) = &self.region {
            response.headers_mut().insert(REGION_HEADER, region.clone());
        }
    }
}

#[cfg(test)]
mod tests {
    use axum::body::Body;

    use super::*;

    #[test]
    fn stamps_the_region_on_a_response() {
        let mut response = Response::new(Body::empty());
        ServedBy::new("us-central").apply(&mut response);

        assert_eq!(response.headers()[&REGION_HEADER], "us-central");
    }

    #[test]
    fn omits_a_region_it_cannot_send_as_a_header() {
        for region in ["", "us\ncentral"] {
            let mut response = Response::new(Body::empty());
            ServedBy::new(region).apply(&mut response);

            assert!(response.headers().get(&REGION_HEADER).is_none());
        }
    }
}
