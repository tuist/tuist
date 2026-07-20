
use super::*;

#[test]
fn node_id_uses_host_when_url_is_parseable() {
    assert_eq!(
        node_id_from_url("https://kura-0.acme.internal:7443"),
        "kura-0.acme.internal"
    );
}

#[test]
fn node_id_falls_back_to_raw_string_for_unparseable_url() {
    assert_eq!(node_id_from_url("not a url"), "not a url");
}

#[test]
fn heartbeat_serializes_generic_fields_only() {
    let payload = RegistrationHeartbeat {
        schema_version: SCHEMA_VERSION,
        node_id: "kura-0",
        tenant_id: "acme",
        region: Some("us-office"),
        advertised_http_url: "https://cache.acme.internal",
        ready: true,
        version: "0.0.0",
        traffic_state: "serving",
        ring_members: 3,
        writer_lock_owned: true,
        observed_at_unix_seconds: 1,
    };

    let json = serde_json::to_string(&payload).expect("serializes");
    assert!(json.contains("\"advertised_http_url\":\"https://cache.acme.internal\""));
    assert!(json.contains("\"tenant_id\":\"acme\""));
    assert!(!json.to_lowercase().contains("tuist"));
}
