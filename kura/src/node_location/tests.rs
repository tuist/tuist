
use super::*;

#[test]
fn country_from_region_handles_known_cloud_and_country_prefix_regions() {
    assert_eq!(country_from_region("fr-par"), Some("FR".into()));
    assert_eq!(country_from_region("us-east"), Some("US".into()));
    assert_eq!(country_from_region("eu-central"), Some("DE".into()));
    assert_eq!(country_from_region("eu-central-1"), Some("DE".into()));
}

#[test]
fn country_from_region_omits_synthetic_non_country_prefixes() {
    assert_eq!(country_from_region("eu-west"), None);
    assert_eq!(country_from_region("ap-south"), None);
    assert_eq!(country_from_region("local"), None);
}

#[test]
fn country_from_subdivision_extracts_iso_country() {
    assert_eq!(country_from_subdivision("US-CA"), Some("US".into()));
    assert_eq!(country_from_subdivision("de-by"), Some("DE".into()));
    assert_eq!(country_from_subdivision("bogus"), None);
}

#[test]
fn probe_is_skipped_when_overrides_already_cover_country_and_subdivision() {
    assert!(!should_probe_geoip(Some("DE"), Some("DE-BY")));
    assert!(!should_probe_geoip(None, Some("US-CA")));
    assert!(should_probe_geoip(Some("DE"), None));
    assert!(should_probe_geoip(None, None));
}

#[tokio::test]
async fn resolve_uses_country_override_when_provided() {
    let location = resolve_node_location(Some(" de "), None, None, "fr-par").await;
    assert_eq!(location.country.as_deref(), Some("DE"));
    assert_eq!(location.subdivision, None);
}

#[tokio::test]
async fn resolve_uses_subdivision_override_to_derive_country() {
    let location = resolve_node_location(None, Some(" us-ca "), None, "fr-par").await;
    assert_eq!(location.country.as_deref(), Some("US"));
    assert_eq!(location.subdivision.as_deref(), Some("US-CA"));
}

#[tokio::test]
async fn resolve_falls_back_to_known_region_country_when_geoip_absent() {
    let location = resolve_node_location(None, None, None, "us-east").await;
    assert_eq!(location.country.as_deref(), Some("US"));
    assert_eq!(location.subdivision, None);
}

#[tokio::test]
async fn resolve_returns_empty_when_everything_fails() {
    let location = resolve_node_location(None, None, None, "??").await;
    assert_eq!(location, NodeLocation::default());
}
