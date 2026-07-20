
use super::{OtlpTraceProtocol, otlp_trace_exporter_config};

#[test]
fn otlp_trace_exporter_config_uses_http_for_signal_paths() {
    let config = otlp_trace_exporter_config("http://collector:4318/v1/traces")
        .expect("expected OTLP HTTP endpoint to parse");

    assert_eq!(config.protocol, OtlpTraceProtocol::HttpBinary);
    assert_eq!(config.endpoint, "http://collector:4318/v1/traces");
}

#[test]
fn otlp_trace_exporter_config_uses_grpc_for_root_endpoint() {
    let config = otlp_trace_exporter_config("http://collector:4317")
        .expect("expected OTLP gRPC endpoint to parse");

    assert_eq!(config.protocol, OtlpTraceProtocol::Grpc);
    assert_eq!(config.endpoint, "http://collector:4317/");
}

#[test]
fn otlp_trace_exporter_config_supports_grpc_scheme_shorthand() {
    let config = otlp_trace_exporter_config("grpcs://collector.internal:443")
        .expect("expected explicit gRPC scheme to parse");

    assert_eq!(config.protocol, OtlpTraceProtocol::Grpc);
    assert_eq!(config.endpoint, "https://collector.internal:443");
}

#[test]
fn otlp_trace_exporter_config_rejects_invalid_urls() {
    let error =
        otlp_trace_exporter_config("not-a-url").expect_err("expected invalid endpoint to fail");

    assert!(error.contains("must be a valid URL"));
}
