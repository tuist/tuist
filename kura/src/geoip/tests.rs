
use super::*;

#[test]
fn open_at_returns_none_when_database_missing() {
    let geoip = GeoIp::open_at(Path::new("/tmp/does-not-exist-kura-geoip.mmdb"));
    assert!(geoip.is_none());
}

#[test]
fn previous_year_month_wraps_across_year() {
    assert_eq!(previous_year_month(2026, 1), (2025, 12));
    assert_eq!(previous_year_month(2026, 5), (2026, 4));
}
