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

/// Resolves the node's own country and subdivision once at startup from
/// deployment configuration alone: no network call and no IP geolocation.
/// Country comes from the configured country, the country prefix of the
/// configured subdivision, or - when neither is set - the region name, but
/// only where that name already starts with a real ISO 3166-1 code (for
/// example `fr-par`). Subdivision has no region-derived fallback and is
/// simply omitted when unconfigured, as is a country the region name
/// cannot answer for.
pub fn resolve_node_location(
    country_override: Option<&str>,
    subdivision_override: Option<&str>,
    region: &str,
) -> NodeLocation {
    let country_override = normalized_override(country_override);
    let subdivision = normalized_override(subdivision_override);
    let country = country_override
        .or_else(|| subdivision.as_deref().and_then(country_from_subdivision))
        .or_else(|| country_from_region(region));

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

fn country_from_subdivision(subdivision: &str) -> Option<String> {
    let (country, _) = subdivision.split_once('-')?;
    if country.len() == 2 && country.chars().all(|c| c.is_ascii_alphabetic()) {
        Some(country.to_ascii_uppercase())
    } else {
        None
    }
}

/// Region names are Tuist-internal ids, not geography, so this answers only
/// for the ones that happen to start with an ISO 3166-1 code (`fr-par`) and
/// stays silent otherwise. It is the last resort behind explicit country and
/// subdivision configuration, which is what every managed region sets.
fn country_from_region(region: &str) -> Option<String> {
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
    fn country_from_region_handles_country_prefix_regions() {
        assert_eq!(country_from_region("fr-par"), Some("FR".into()));
        assert_eq!(country_from_region("us-east"), Some("US".into()));
        assert_eq!(country_from_region("us-west-1"), Some("US".into()));
    }

    #[test]
    fn country_from_region_omits_synthetic_non_country_prefixes() {
        // `eu-central` names a region served from France today, so the
        // continent prefix must stay unanswered rather than guess a country.
        assert_eq!(country_from_region("eu-central"), None);
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

    /// The managed fleets configure both halves, which is the whole point of
    /// the change that removed the startup geolocation probe: resolution is a
    /// pure function of configuration, so it cannot reach the network.
    #[test]
    fn resolve_uses_configured_country_and_subdivision_without_probing() {
        let location = resolve_node_location(Some(" fr "), Some(" fr-idf "), "eu-central");
        assert_eq!(location.country.as_deref(), Some("FR"));
        assert_eq!(location.subdivision.as_deref(), Some("FR-IDF"));
    }

    #[test]
    fn resolve_uses_country_override_when_provided() {
        let location = resolve_node_location(Some(" de "), None, "fr-par");
        assert_eq!(location.country.as_deref(), Some("DE"));
        assert_eq!(location.subdivision, None);
    }

    #[test]
    fn resolve_uses_subdivision_override_to_derive_country() {
        let location = resolve_node_location(None, Some(" us-ca "), "fr-par");
        assert_eq!(location.country.as_deref(), Some("US"));
        assert_eq!(location.subdivision.as_deref(), Some("US-CA"));
    }

    #[test]
    fn resolve_prefers_the_country_override_over_the_subdivision_prefix() {
        let location = resolve_node_location(Some("us"), Some("fr-idf"), "fr-par");
        assert_eq!(location.country.as_deref(), Some("US"));
        assert_eq!(location.subdivision.as_deref(), Some("FR-IDF"));
    }

    #[test]
    fn resolve_falls_back_to_the_region_country_when_nothing_is_configured() {
        let location = resolve_node_location(None, None, "us-east");
        assert_eq!(location.country.as_deref(), Some("US"));
        assert_eq!(location.subdivision, None);
    }

    #[test]
    fn resolve_returns_empty_when_the_region_carries_no_country() {
        let location = resolve_node_location(None, None, "??");
        assert_eq!(location, NodeLocation::default());
    }
}
