use std::{net::IpAddr, time::Duration};

use reqwest::Client;

use crate::geoip::GeoIp;

/// Public IP discovery endpoint used to derive the node's geographic
/// location at startup. The endpoint returns the caller's egress IP
/// as plain text. We only hit it once per pod lifetime — the result
/// becomes a Resource attribute on every exported span, so a slow or
/// failed probe degrades to the region-prefix fallback rather than
/// holding up startup beyond [`PROBE_TIMEOUT`].
const EGRESS_IP_ENDPOINT: &str = "https://api.ipify.org";
const PROBE_TIMEOUT: Duration = Duration::from_secs(3);

pub async fn resolve_node_country(
    override_value: Option<&str>,
    geoip: Option<&GeoIp>,
    region: &str,
) -> Option<String> {
    if let Some(country) = override_value
        && !country.trim().is_empty()
    {
        return Some(country.trim().to_ascii_uppercase());
    }
    if let Some(geoip) = geoip
        && let Some(ip) = fetch_egress_ip().await
        && let Some(country) = geoip.country_code(ip)
    {
        return Some(country);
    }
    iso_prefix_from_region(region)
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
    async fn resolve_uses_override_when_provided() {
        let country = resolve_node_country(Some(" de "), None, "fr-par").await;
        assert_eq!(country.as_deref(), Some("DE"));
    }

    #[tokio::test]
    async fn resolve_falls_back_to_region_prefix_when_geoip_absent() {
        let country = resolve_node_country(None, None, "us-east").await;
        assert_eq!(country.as_deref(), Some("US"));
    }

    #[tokio::test]
    async fn resolve_returns_none_when_everything_fails() {
        let country = resolve_node_country(None, None, "??").await;
        assert!(country.is_none());
    }
}
