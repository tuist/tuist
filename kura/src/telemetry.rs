use std::{
    collections::BTreeMap,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};

use axum::http::HeaderMap;
use opentelemetry::{
    KeyValue, global,
    propagation::{Extractor, Injector},
    trace::{TraceContextExt, TracerProvider as _},
};
use opentelemetry_otlp::{Protocol, WithExportConfig, WithHttpConfig};
use opentelemetry_sdk::{
    Resource,
    propagation::TraceContextPropagator,
    trace::{Sampler, SdkTracerProvider},
};
use sentry::{ClientInitGuard, ClientOptions};
use tracing::{Span, field, info, warn};
use tracing_opentelemetry::{OpenTelemetrySpanExt, SetParentError};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use crate::{VERSION, config::Config, node_location::NodeLocation};

static TRACE_EXPORT_ACTIVE: AtomicBool = AtomicBool::new(false);

pub struct TelemetryGuards {
    tracer_provider: Option<SdkTracerProvider>,
    sentry_guard: Option<ClientInitGuard>,
}

impl TelemetryGuards {
    pub fn shutdown(self) {
        if let Some(provider) = self.tracer_provider
            && let Err(error) = provider.shutdown()
        {
            warn!(
                event.name = "kura.telemetry.shutdown_failed",
                error = %error,
                "failed to shut down trace exporter"
            );
        }

        drop(self.sentry_guard);
    }
}

pub fn init_tracing(config: &Config, node_location: &NodeLocation) -> TelemetryGuards {
    global::set_text_map_propagator(TraceContextPropagator::new());

    let env_filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| "kura=info".into());
    let fmt_layer = tracing_subscriber::fmt::layer()
        .json()
        .flatten_event(true)
        .with_current_span(true)
        .with_span_list(true)
        .with_ansi(false);
    let sentry_guard = init_sentry(config);

    let tracer_result = config
        .otlp_traces_endpoint
        .as_deref()
        .map(|endpoint| build_tracer_provider(config, endpoint, node_location));

    match tracer_result {
        Some(Ok(tracer_provider)) => {
            let tracer = tracer_provider.tracer("kura");
            if sentry_guard.is_some() {
                tracing_subscriber::registry()
                    .with(env_filter)
                    .with(fmt_layer)
                    .with(tracing_opentelemetry::layer().with_tracer(tracer))
                    .with(sentry::integrations::tracing::layer())
                    .init();
            } else {
                tracing_subscriber::registry()
                    .with(env_filter)
                    .with(fmt_layer)
                    .with(tracing_opentelemetry::layer().with_tracer(tracer))
                    .init();
            }
            TRACE_EXPORT_ACTIVE.store(true, Ordering::Relaxed);
            info!(
                event.name = "kura.telemetry.tracing_active",
                service.name = %config.otel_service_name,
                service.version = VERSION,
                "OpenTelemetry tracing active"
            );
            TelemetryGuards {
                tracer_provider: Some(tracer_provider),
                sentry_guard,
            }
        }
        Some(Err(error)) => {
            TRACE_EXPORT_ACTIVE.store(false, Ordering::Relaxed);
            if sentry_guard.is_some() {
                tracing_subscriber::registry()
                    .with(env_filter)
                    .with(fmt_layer)
                    .with(sentry::integrations::tracing::layer())
                    .init();
            } else {
                tracing_subscriber::registry()
                    .with(env_filter)
                    .with(fmt_layer)
                    .init();
            }
            warn!(
                event.name = "kura.telemetry.initialization_failed",
                error = %error,
                service.name = %config.otel_service_name,
                service.version = VERSION,
                "failed to initialize OpenTelemetry tracing"
            );
            TelemetryGuards {
                tracer_provider: None,
                sentry_guard,
            }
        }
        None => {
            TRACE_EXPORT_ACTIVE.store(false, Ordering::Relaxed);
            if sentry_guard.is_some() {
                tracing_subscriber::registry()
                    .with(env_filter)
                    .with(fmt_layer)
                    .with(sentry::integrations::tracing::layer())
                    .init();
            } else {
                tracing_subscriber::registry()
                    .with(env_filter)
                    .with(fmt_layer)
                    .init();
            }
            info!(
                event.name = "kura.telemetry.tracing_disabled",
                service.name = %config.otel_service_name,
                service.version = VERSION,
                "OpenTelemetry tracing disabled because no endpoint is configured"
            );
            TelemetryGuards {
                tracer_provider: None,
                sentry_guard,
            }
        }
    }
}

pub fn trace_export_active() -> bool {
    TRACE_EXPORT_ACTIVE.load(Ordering::Relaxed)
}

pub fn log_context_span(config: &Config, node_location: &NodeLocation) -> Span {
    let span = tracing::info_span!(
        "kura.runtime",
        service.name = %config.otel_service_name,
        service.namespace = "kura",
        service.version = VERSION,
        deployment.environment.name = %config.otel_deployment_environment,
        kura.region = %config.region,
        kura.tenant_id = %config.tenant_id,
        geo.country.iso_code = field::Empty,
        geo.region.iso_code = field::Empty,
        service.instance.id = %config.node_url,
        trace_id = field::Empty,
        span_id = field::Empty,
    );
    if let Some(country) = node_location.country.as_deref() {
        span.record("geo.country.iso_code", country);
    }
    if let Some(subdivision) = node_location.subdivision.as_deref() {
        span.record("geo.region.iso_code", subdivision);
    }
    record_trace_context(&span);
    span
}

pub fn record_trace_context(span: &Span) {
    let context = span.context();
    let span_ref = context.span();
    let span_context = span_ref.span_context();
    if span_context.is_valid() {
        span.record("trace_id", field::display(span_context.trace_id()));
        span.record("span_id", field::display(span_context.span_id()));
    }
}

fn init_sentry(config: &Config) -> Option<ClientInitGuard> {
    let dsn = config.sentry_dsn.as_deref()?;

    Some(sentry::init(ClientOptions {
        dsn: Some(
            dsn.parse()
                .expect("sentry dsn should be valid when configuration is valid"),
        ),
        environment: Some(config.otel_deployment_environment.clone().into()),
        release: Some(format!("kura@{VERSION}").into()),
        server_name: Some(config.otel_service_name.clone().into()),
        transport: Some(Arc::new(|options: &ClientOptions| {
            let client = sentry_http_client_builder(options)
                .expect("failed to configure Sentry TLS trust")
                .build()
                .expect("failed to build Sentry HTTP client");
            Arc::new(sentry::transports::ReqwestHttpTransport::with_client(
                options, client,
            )) as Arc<dyn sentry::Transport>
        })),
        ..Default::default()
    }))
}

fn sentry_http_client_builder(options: &ClientOptions) -> Result<reqwest::ClientBuilder, String> {
    if options.accept_invalid_certs {
        tracing::warn!(
            "Sentry invalid-certificate override ignored; native TLS verification is required"
        );
    }
    let mut builder = crate::certificate_trust::client_builder()?;
    // Defaults are applied before the TransportFactory runs. Preserve the SDK's
    // explicit per-scheme proxies (including its HTTPS-to-HTTP proxy fallback).
    for (https, url) in [(false, &options.http_proxy), (true, &options.https_proxy)] {
        if let Some(url) = url {
            let proxy = if https {
                reqwest::Proxy::https(url.as_ref())
            } else {
                reqwest::Proxy::http(url.as_ref())
            };
            match proxy {
                Ok(proxy) => builder = builder.proxy(proxy),
                Err(_) => tracing::warn!("invalid Sentry proxy configuration ignored"),
            }
        }
    }
    Ok(builder)
}

fn build_tracer_provider(
    config: &Config,
    endpoint: &str,
    node_location: &NodeLocation,
) -> Result<SdkTracerProvider, String> {
    let exporter = build_span_exporter(endpoint)?;

    let mut attributes = vec![
        KeyValue::new("service.name", config.otel_service_name.clone()),
        KeyValue::new("service.namespace", "kura"),
        KeyValue::new("service.version", VERSION),
        KeyValue::new(
            "deployment.environment.name",
            config.otel_deployment_environment.clone(),
        ),
        KeyValue::new("kura.region", config.region.clone()),
        KeyValue::new("kura.tenant_id", config.tenant_id.clone()),
        KeyValue::new("service.instance.id", config.node_url.clone()),
    ];
    if let Some(country) = node_location.country.as_deref() {
        attributes.push(KeyValue::new("geo.country.iso_code", country.to_owned()));
    }
    if let Some(subdivision) = node_location.subdivision.as_deref() {
        attributes.push(KeyValue::new("geo.region.iso_code", subdivision.to_owned()));
    }
    let resource = Resource::builder_empty()
        .with_attributes(attributes)
        .build();

    Ok(SdkTracerProvider::builder()
        .with_sampler(Sampler::ParentBased(Box::new(Sampler::TraceIdRatioBased(
            1.0,
        ))))
        .with_resource(resource)
        .with_batch_exporter(exporter)
        .build())
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum OtlpTraceProtocol {
    Grpc,
    HttpBinary,
}

#[derive(Debug, Eq, PartialEq)]
struct OtlpTraceExporterConfig {
    endpoint: String,
    protocol: OtlpTraceProtocol,
}

fn build_span_exporter(endpoint: &str) -> Result<opentelemetry_otlp::SpanExporter, String> {
    let exporter = otlp_trace_exporter_config(endpoint)?;

    match exporter.protocol {
        OtlpTraceProtocol::Grpc => opentelemetry_otlp::SpanExporter::builder()
            .with_tonic()
            .with_endpoint(exporter.endpoint)
            .with_timeout(export_timeout())
            .build()
            .map_err(|error| format!("failed to build OTLP gRPC exporter: {error}")),
        OtlpTraceProtocol::HttpBinary => opentelemetry_otlp::SpanExporter::builder()
            .with_http()
            .with_http_client(build_otlp_http_client()?)
            .with_endpoint(exporter.endpoint)
            .with_protocol(Protocol::HttpBinary)
            .with_timeout(export_timeout())
            .build()
            .map_err(|error| format!("failed to build OTLP HTTP exporter: {error}")),
    }
}

fn export_timeout() -> Duration {
    Duration::from_secs(crate::control_plane_http::REQUEST_TIMEOUT_SECS)
}

// The exporter crate's default client sets only a total timeout, so DNS, TCP,
// TLS and the batch upload share one budget. A remote region can spend more
// than a second resolving Kubernetes search domains, which then leaves too
// little of it for the upload and fails the export. Give connection setup the
// same dedicated budget the control-plane client gets.
//
// The client has to be blocking: the batch processor drives exports with
// `futures_executor::block_on` on its own thread, which has no Tokio reactor to
// drive an asynchronous client's I/O. Building it off-runtime is what the
// exporter crate does internally, and is required because `reqwest::blocking`
// panics when constructed inside one.
fn build_otlp_http_client() -> Result<reqwest::blocking::Client, String> {
    std::thread::spawn(|| {
        otlp_http_client_builder()?
            .build()
            .map_err(|_| "failed to build OTLP HTTP client".to_string())
    })
    .join()
    .map_err(|_| "OTLP HTTP client builder thread panicked".to_string())?
}

fn otlp_http_client_builder() -> Result<reqwest::blocking::ClientBuilder, String> {
    Ok(reqwest::blocking::Client::builder()
        .tls_backend_preconfigured(crate::certificate_trust::native_config()?)
        .connect_timeout(Duration::from_secs(
            crate::control_plane_http::CONNECT_TIMEOUT_SECS,
        ))
        .timeout(export_timeout()))
}

fn otlp_trace_exporter_config(endpoint: &str) -> Result<OtlpTraceExporterConfig, String> {
    let url = reqwest::Url::parse(endpoint)
        .map_err(|error| format!("OTLP traces endpoint must be a valid URL: {error}"))?;

    let (protocol, endpoint) = match url.scheme() {
        "grpc" => (
            OtlpTraceProtocol::Grpc,
            endpoint.replacen("grpc://", "http://", 1),
        ),
        "grpcs" => (
            OtlpTraceProtocol::Grpc,
            endpoint.replacen("grpcs://", "https://", 1),
        ),
        _ if url.path().is_empty() || url.path() == "/" => {
            (OtlpTraceProtocol::Grpc, url.to_string())
        }
        _ => (OtlpTraceProtocol::HttpBinary, url.to_string()),
    };

    Ok(OtlpTraceExporterConfig { endpoint, protocol })
}

struct RequestHeaderExtractor<'a>(&'a HeaderMap);

impl Extractor for RequestHeaderExtractor<'_> {
    fn get(&self, key: &str) -> Option<&str> {
        self.0.get(key).and_then(|value| value.to_str().ok())
    }

    fn keys(&self) -> Vec<&str> {
        self.0.keys().map(|name| name.as_str()).collect()
    }
}

struct ReqwestHeaderInjector<'a>(&'a mut reqwest::header::HeaderMap);

struct MapHeaderExtractor<'a>(&'a BTreeMap<String, String>);

impl Extractor for MapHeaderExtractor<'_> {
    fn get(&self, key: &str) -> Option<&str> {
        self.0.get(key).map(String::as_str)
    }

    fn keys(&self) -> Vec<&str> {
        self.0.keys().map(String::as_str).collect()
    }
}

impl Injector for ReqwestHeaderInjector<'_> {
    fn set(&mut self, key: &str, value: String) {
        let Ok(name) = reqwest::header::HeaderName::from_bytes(key.as_bytes()) else {
            return;
        };
        let Ok(value) = reqwest::header::HeaderValue::from_str(&value) else {
            return;
        };
        self.0.insert(name, value);
    }
}

pub fn extract_parent_context(headers: &HeaderMap) -> opentelemetry::Context {
    global::get_text_map_propagator(|propagator| {
        propagator.extract(&RequestHeaderExtractor(headers))
    })
}

pub fn inject_current_trace_context(headers: &mut reqwest::header::HeaderMap) {
    let context = Span::current().context();
    global::get_text_map_propagator(|propagator| {
        let mut injector = ReqwestHeaderInjector(headers);
        propagator.inject_context(&context, &mut injector);
    });
}

pub fn attach_parent_context(span: &Span, headers: &HeaderMap) {
    attach_extracted_parent_context(span, extract_parent_context(headers));
}

pub fn attach_parent_context_from_map(span: &Span, headers: &BTreeMap<String, String>) {
    let context = global::get_text_map_propagator(|propagator| {
        propagator.extract(&MapHeaderExtractor(headers))
    });
    attach_extracted_parent_context(span, context);
}

fn attach_extracted_parent_context(span: &Span, context: opentelemetry::Context) {
    if let Err(error) = span.set_parent(context)
        && should_warn_about_parent_context_error(&error)
    {
        warn!(
            error = ?error,
            event.name = "kura.telemetry.parent_context.attach_failed",
            "failed to attach propagated trace context"
        );
    }
}

fn should_warn_about_parent_context_error(error: &SetParentError) -> bool {
    matches!(error, SetParentError::AlreadyStarted)
}

#[cfg(test)]
mod tests {
    use tracing_opentelemetry::SetParentError;

    use std::{
        net::SocketAddr,
        sync::Arc,
        time::{Duration, Instant},
    };

    use reqwest::dns::{Addrs, Name, Resolve, Resolving};

    use super::{
        OtlpTraceProtocol, export_timeout, otlp_http_client_builder, otlp_trace_exporter_config,
        sentry_http_client_builder, should_warn_about_parent_context_error,
    };

    #[tokio::test]
    async fn sentry_invalid_certificate_option_cannot_disable_native_verification() {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let fixture = rcgen::generate_simple_self_signed(vec!["localhost".into()]).unwrap();
        let key =
            rustls::pki_types::PrivateKeyDer::Pkcs8(fixture.signing_key.serialize_der().into());
        let server = rustls::ServerConfig::builder_with_provider(Arc::new(
            rustls::crypto::aws_lc_rs::default_provider(),
        ))
        .with_safe_default_protocol_versions()
        .unwrap()
        .with_no_client_auth()
        .with_single_cert(vec![fixture.cert.der().clone()], key)
        .unwrap();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let task = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            if let Ok(mut tls) = tokio_rustls::TlsAcceptor::from(Arc::new(server))
                .accept(stream)
                .await
            {
                let mut bytes = [0; 1024];
                let count = tls.read(&mut bytes).await.unwrap_or(0);
                if count > 0 {
                    tls.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
                        .await
                        .unwrap();
                }
                return count;
            }
            0
        });
        let options = sentry::ClientOptions {
            accept_invalid_certs: true,
            ..Default::default()
        };
        let client = sentry_http_client_builder(&options)
            .unwrap()
            .no_proxy()
            .timeout(Duration::from_secs(3))
            .build()
            .unwrap();
        let error = client
            .get(format!("https://localhost:{}/", address.port()))
            .send()
            .await
            .unwrap_err();
        assert!(crate::certificate_trust::terminal_transport_failure(&error));
        assert_eq!(
            tokio::time::timeout(Duration::from_secs(3), task)
                .await
                .unwrap()
                .unwrap(),
            0
        );
    }

    #[tokio::test]
    async fn sentry_retains_defaulted_explicit_http_and_https_proxies() {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        for https in [false, true] {
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let address = listener.local_addr().unwrap();
            let task = tokio::spawn(async move {
                let (mut stream, _) = listener.accept().await.unwrap();
                let mut request = [0; 4096];
                let count = stream.read(&mut request).await.unwrap();
                let request = String::from_utf8(request[..count].to_vec()).unwrap();
                let response = if https {
                    b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n".as_slice()
                } else {
                    b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n".as_slice()
                };
                stream.write_all(response).await.unwrap();
                request
            });
            let proxy = format!("http://{address}");
            let options = sentry::ClientOptions {
                http_proxy: (!https).then(|| proxy.clone().into()),
                https_proxy: https.then(|| proxy.into()),
                ..Default::default()
            };
            let client = sentry_http_client_builder(&options)
                .unwrap()
                .timeout(Duration::from_secs(3))
                .build()
                .unwrap();
            let scheme = if https { "https" } else { "http" };
            let result = client
                .get(format!("{scheme}://not-resolved.invalid/event"))
                .send()
                .await;
            if https {
                assert!(result.is_err());
            } else {
                assert_eq!(result.unwrap().status(), reqwest::StatusCode::OK);
            }
            let request = tokio::time::timeout(Duration::from_secs(3), task)
                .await
                .unwrap()
                .unwrap();
            assert!(request.starts_with(if https {
                "CONNECT not-resolved.invalid:443 "
            } else {
                "GET http://not-resolved.invalid/event "
            }));
        }
    }

    struct StalledResolver;

    impl Resolve for StalledResolver {
        fn resolve(&self, _: Name) -> Resolving {
            Box::pin(async move {
                tokio::time::sleep(Duration::from_secs(60)).await;
                let address: SocketAddr = "127.0.0.1:1".parse().unwrap();
                Ok(Box::new(std::iter::once(address)) as Addrs)
            })
        }
    }

    // The exporter crate's default client leaves connection setup sharing the
    // export deadline, so a slow resolve consumes the budget the upload needs.
    #[test]
    fn stalled_dns_fails_the_export_on_the_connect_budget() {
        let client = otlp_http_client_builder()
            .unwrap()
            .no_proxy()
            .dns_resolver(Arc::new(StalledResolver))
            .build()
            .expect("expected the OTLP HTTP client to build");

        let started = Instant::now();
        let error = client
            .post("http://collector.test:4318/v1/traces")
            .send()
            .expect_err("expected the stalled resolve to time out");

        assert!(error.is_timeout());
        assert!(
            started.elapsed()
                >= Duration::from_secs(crate::control_plane_http::CONNECT_TIMEOUT_SECS)
        );
        assert!(started.elapsed() < export_timeout());
    }

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

    #[test]
    fn missing_or_filtered_tracing_layers_do_not_emit_warnings() {
        assert!(!should_warn_about_parent_context_error(
            &SetParentError::LayerNotFound
        ));
        assert!(!should_warn_about_parent_context_error(
            &SetParentError::SpanDisabled
        ));
    }

    #[test]
    fn an_already_started_span_emits_a_warning() {
        assert!(should_warn_about_parent_context_error(
            &SetParentError::AlreadyStarted
        ));
    }
}
