//! Which Kura region answered this proxy's REAPI traffic.
//!
//! A managed account's stable hostname (`<handle>.cache.tuist.dev`) is routed
//! by latency records the client's resolver picks, so a VPN or a corporate
//! resolver can send a build to a region far from where the machine is. Kura
//! names its region on every response (`x-kura-region`); the proxy records it
//! next to each read and write in `cas_analytics.db`, and the server compares
//! it with where the build came from.

use std::sync::{Arc, RwLock};

use tonic::metadata::MetadataMap;

pub const REGION_HEADER: &str = "x-kura-region";

/// Longest region label accepted. Region ids are short; anything longer is not
/// one and is not worth storing.
const MAX_REGION_BYTES: usize = 64;

#[derive(Default)]
pub struct ServedByCell {
    region: RwLock<Option<Arc<str>>>,
}

impl ServedByCell {
    /// Records the region that answered a call. A response from a Kura that
    /// predates the header leaves the cell as it was.
    pub fn observe(&self, metadata: &MetadataMap) {
        let Some(region) = region(metadata) else {
            return;
        };
        if self.region.read().unwrap().as_deref() == Some(region) {
            return;
        }
        *self.region.write().unwrap() = Some(region.into());
    }

    pub fn current(&self) -> Option<Arc<str>> {
        self.region.read().unwrap().clone()
    }
}

fn region(metadata: &MetadataMap) -> Option<&str> {
    let value = metadata.get(REGION_HEADER)?.to_str().ok()?.trim();
    let valid = !value.is_empty()
        && value.len() <= MAX_REGION_BYTES
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.'));
    valid.then_some(value)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn metadata(region: &str) -> MetadataMap {
        let mut metadata = MetadataMap::new();
        metadata.insert(REGION_HEADER, region.parse().unwrap());
        metadata
    }

    #[test]
    fn records_the_region_that_answered() {
        let cell = ServedByCell::default();
        cell.observe(&metadata("us-central"));
        assert_eq!(cell.current().as_deref(), Some("us-central"));

        cell.observe(&metadata("ap-southeast"));
        assert_eq!(cell.current().as_deref(), Some("ap-southeast"));
    }

    #[test]
    fn a_kura_without_the_header_leaves_it_as_it_was() {
        let cell = ServedByCell::default();
        cell.observe(&MetadataMap::new());
        assert_eq!(cell.current(), None);

        cell.observe(&metadata("us-central"));
        cell.observe(&MetadataMap::new());
        assert_eq!(cell.current().as_deref(), Some("us-central"));
    }

    #[test]
    fn refuses_values_that_are_not_region_ids() {
        let cell = ServedByCell::default();
        cell.observe(&metadata("us central; drop"));
        cell.observe(&metadata(&"a".repeat(MAX_REGION_BYTES + 1)));
        assert_eq!(cell.current(), None);
    }
}
