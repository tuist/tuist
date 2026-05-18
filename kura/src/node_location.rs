use std::{net::IpAddr, time::Duration};

use reqwest::Client;

use crate::geoip::GeoIp;

/// Public IP discovery endpoint used to derive the node's geographic
/// location at startup. The endpoint returns the caller's egress IP
/// as plain text. We only hit it once per pod lifetime; the result
/// becomes a Resource attribute on every exported span, so a slow or
/// failed probe degrades to the region-prefix fallback rather than
/// holding up startup beyond [`PROBE_TIMEOUT`].
const EGRESS_IP_ENDPOINT: &str = "https://api.ipify.org";
const PROBE_TIMEOUT: Duration = Duration::from_secs(3);

/// The serving node's own coarse location, stamped once at startup onto
/// the OTel Resource (using the `geo.*` semantic conventions) so every
/// exported span carries it.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct NodeLocation {
    /// ISO 3166-1 alpha-2 country code, e.g. `FR`. Emitted as
    /// `geo.country.iso_code`.
    pub country: Option<String>,
    /// ISO 3166-2 subdivision code, e.g. `US-CA`. Emitted as
    /// `geo.region.iso_code`.
    pub subdivision: Option<String>,
}

/// Resolves the node's own country and subdivision once at startup. The
/// egress-IP probe and GeoIP lookup happen at most once and feed both
/// fields when an operator override does not already answer the question.
/// Country falls back to a known deployment-region mapping or, when the
/// region prefix is already a real ISO 3166-1 code (for example `fr-par`),
/// that prefix directly. Subdivision has no region-derived fallback and is
/// simply omitted when unknown.
pub async fn resolve_node_location(
    country_override: Option<&str>,
    subdivision_override: Option<&str>,
    geoip: Option<&GeoIp>,
    region: &str,
) -> NodeLocation {
    let country_override = normalized_override(country_override);
    let subdivision_override = normalized_override(subdivision_override);
    let subdivision_country = subdivision_override
        .as_deref()
        .and_then(country_from_subdivision);
    let probed = if let Some(geoip) = geoip
        && should_probe_geoip(country_override.as_deref(), subdivision_override.as_deref())
    {
        match fetch_egress_ip().await {
            Some(ip) => geoip.locate(ip),
            None => None,
        }
    } else {
        None
    };

    let country = country_override
        .or(subdivision_country)
        .or_else(|| {
            probed
                .as_ref()
                .and_then(|location| location.country.clone())
        })
        .or_else(|| country_from_region(region));
    let subdivision = subdivision_override.or_else(|| {
        probed
            .as_ref()
            .and_then(|location| location.subdivision.clone())
    });

    NodeLocation {
        country,
        subdivision,
    }
}

fn normalized_override(value: Option<&str>) -> Option<String> {
    value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.to_ascii_uppercase())
}

fn should_probe_geoip(country: Option<&str>, subdivision: Option<&str>) -> bool {
    let needs_country =
        country.is_none() && subdivision.and_then(country_from_subdivision).is_none();
    let needs_subdivision = subdivision.is_none();
    needs_country || needs_subdivision
}

async fn fetch_egress_ip() -> Option<IpAddr> {
    let client = Client::builder().timeout(PROBE_TIMEOUT).build().ok()?;
    let response = client.get(EGRESS_IP_ENDPOINT).send().await.ok()?;
    let text = response.text().await.ok()?;
    text.trim().parse::<IpAddr>().ok()
}

fn country_from_subdivision(subdivision: &str) -> Option<String> {
    let (country, _) = subdivision.split_once('-')?;
    if country.len() == 2 && country.chars().all(|c| c.is_ascii_alphabetic()) {
        Some(country.to_ascii_uppercase())
    } else {
        None
    }
}

fn country_from_region(region: &str) -> Option<String> {
    match region {
        "eu-central" | "eu-central-1" => Some("DE".into()),
        "us-east" | "us-east-1" | "us-west" | "us-west-1" => Some("US".into()),
        _ => country_prefix_from_region(region),
    }
}

fn country_prefix_from_region(region: &str) -> Option<String> {
    let prefix = region.split('-').next()?;
    if prefix.len() != 2 || !prefix.chars().all(|c| c.is_ascii_alphabetic()) {
        return None;
    }
    if matches!(prefix, "af" | "ap" | "eu" | "me" | "na" | "sa") {
        return None;
    }
    Some(prefix.to_ascii_uppercase())
}

#[cfg(test)]
mod tests {
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
}
