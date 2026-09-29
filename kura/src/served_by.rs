//! Names the region that answered each public client request, over REAPI and
//! plain HTTP alike.
//!
//! A managed account's stable hostname is routed by the client's DNS
//! resolver, so which region a client reaches is decided by its network (a
//! VPN, a corporate resolver), not by the control plane. The CAS proxy records
//! this header next to the reads and writes it makes, which is how a build
//! says which region served it. On gRPC it is sent as initial metadata, so
//! trailers-only error responses carry it too. It is not gated on
//! authentication: the region is not secret, and it matters most when
//! diagnosing a refused request.

use axum::{
    extract::State,
    http::{HeaderName, HeaderValue},
    response::Response,
};

use crate::state::SharedState;

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

    /// The value for responses written as raw HTTP/1.1 rather than through
    /// axum. A `HeaderValue` built from a `&str` is visible ASCII, so it is
    /// safe to write to the socket unescaped.
    pub(crate) fn region(&self) -> Option<&str> {
        self.region.as_ref().and_then(|value| value.to_str().ok())
    }

    pub(crate) fn apply(&self, response: &mut Response) {
        if let Some(region) = &self.region {
            response.headers_mut().insert(REGION_HEADER, region.clone());
        }
    }
}

pub(crate) async fn stamp(State(state): State<SharedState>, mut response: Response) -> Response {
    state.served_by.apply(&mut response);
    response
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
        assert_eq!(ServedBy::new("us-central").region(), Some("us-central"));
    }

    #[test]
    fn omits_a_region_it_cannot_send_as_a_header() {
        for region in ["", "us\ncentral"] {
            let mut response = Response::new(Body::empty());
            ServedBy::new(region).apply(&mut response);

            assert!(response.headers().get(&REGION_HEADER).is_none());
            assert_eq!(ServedBy::new(region).region(), None);
        }
    }
}
