# Repeated attribute keys from real SDK exporters

OTLP says attribute keys are unique, but widely used SDKs export repeats. The
Collector and Tempo keep these spans; Pulse keeps the last occurrence of each
owner-level key and adds the discarded ones to `droppedAttributesCount`.

- `erlang-sdk.protobuf`: the `../elixir_sdk` modern producer (API 1.5.0, SDK
  1.7.0, exporter 1.10.0, Bandit instrumentation 0.3.0, Phoenix 2.0.1) with
  `erlang_fixture_plug.exs.txt` as its plug. Bandit instrumentation sets atom
  semantic-convention keys (`:"client.address"`, `:"url.path"`); the plug sets
  the same names as binaries, as an application request plug does. The Erlang
  attribute map keeps both, and `otel_otlp_common:to_attributes/1` emits two
  pairs per name. Captured with the producer's `SDKCaptureExporter` (generated
  `encode_msg` of `otel_otlp_traces:to_proto/2`).
- `rust-sdk.protobuf`: `rust_producer.rs.txt` with
  `rust_producer.Cargo.toml.txt` (opentelemetry 0.32.0, opentelemetry_sdk
  0.32.1, opentelemetry-proto 0.32.0, tracing-opentelemetry 0.33.0). A
  `field::Empty` span field recorded twice becomes two pairs, because the SDK
  appends every `set_attribute`. Encoded with opentelemetry-proto's
  `group_spans_by_resource_and_scope`, the OTLP exporter's own transform.

Source times are wall-clock times of the capture run. These files contain no
application data or credentials.
