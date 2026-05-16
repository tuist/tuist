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
/// fields. Country falls back to the region prefix; subdivision has no
/// region-derived fallback and is simply omitted when unknown.
pub async fn resolve_node_location(
    country_override: Option<&str>,
    subdivision_override: Option<&str>,
    geoip: Option<&GeoIp>,
    region: &str,
) -> NodeLocation {
    let probed = match geoip {
        Some(geoip) => match fetch_egress_ip().await {
            Some(ip) => geoip.locate(ip),
            None => None,
        },
        None => None,
    };

    let country = normalized_override(country_override)
        .or_else(|| {
            probed
                .as_ref()
                .and_then(|location| location.country.clone())
        })
        .or_else(|| iso_prefix_from_region(region));
    let subdivision = normalized_override(subdivision_override).or_else(|| {
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

async fn fetch_egress_ip() -> Option<IpAddr> {
    let client = Client::builder().timeout(PROBE_TIMEOUT).build().ok()?;
    let response = client.get(EGRESS_IP_ENDPOINT).send().await.ok()?;
    let text = response.text().await.ok()?;
    text.trim().parse::<IpAddr>().ok()
}

fn iso_prefix_from_region(region: &str) -> Option<String> {
    let prefix: String = region.chars().take(2).collect();
    if prefix.chars().count() == 2 && prefix.chars().all(|c| c.is_ascii_alphabetic()) {
        Some(prefix.to_ascii_uppercase())
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn iso_prefix_handles_dash_separated_regions() {
        assert_eq!(iso_prefix_from_region("fr-par"), Some("FR".into()));
        assert_eq!(iso_prefix_from_region("us-east"), Some("US".into()));
        assert_eq!(iso_prefix_from_region("eu-west"), Some("EU".into()));
    }

    #[test]
    fn iso_prefix_uppercases_the_prefix() {
        assert_eq!(iso_prefix_from_region("nl-ams"), Some("NL".into()));
    }

    #[test]
    fn iso_prefix_returns_none_for_short_or_non_alpha_regions() {
        assert_eq!(iso_prefix_from_region("f"), None);
        assert_eq!(iso_prefix_from_region("1a"), None);
        assert_eq!(iso_prefix_from_region(""), None);
    }

    #[tokio::test]
    async fn resolve_uses_country_override_when_provided() {
        let location = resolve_node_location(Some(" de "), None, None, "fr-par").await;
        assert_eq!(location.country.as_deref(), Some("DE"));
        assert_eq!(location.subdivision, None);
    }

    #[tokio::test]
    async fn resolve_uses_subdivision_override_alongside_region_country() {
        let location = resolve_node_location(None, Some(" us-ca "), None, "fr-par").await;
        assert_eq!(location.country.as_deref(), Some("FR"));
        assert_eq!(location.subdivision.as_deref(), Some("US-CA"));
    }

    #[tokio::test]
    async fn resolve_falls_back_to_region_prefix_when_geoip_absent() {
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
