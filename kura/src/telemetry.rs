use std::time::Duration;

use axum::http::HeaderMap;
use opentelemetry::{
    KeyValue, global,
    propagation::{Extractor, Injector},
    trace::TracerProvider as _,
};
use opentelemetry_otlp::{Protocol, WithExportConfig};
use opentelemetry_sdk::{
    Resource,
    propagation::TraceContextPropagator,
    trace::{Sampler, SdkTracerProvider},
};
use tracing::{Span, warn};
use tracing_opentelemetry::OpenTelemetrySpanExt;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use crate::config::Config;

pub fn init_tracing(config: &Config) -> Option<SdkTracerProvider> {
    global::set_text_map_propagator(TraceContextPropagator::new());

    let env_filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| "kura=info".into());
    let fmt_layer = tracing_subscriber::fmt::layer();

    match build_tracer_provider(config, &config.otlp_traces_endpoint) {
        Ok(tracer_provider) => {
            let tracer = tracer_provider.tracer("kura");
            tracing_subscriber::registry()
                .with(env_filter)
                .with(fmt_layer)
                .with(tracing_opentelemetry::layer().with_tracer(tracer))
                .init();
            Some(tracer_provider)
        }
        Err(error) => {
            eprintln!("failed to initialize OTLP tracing, falling back to logs only: {error}");
            tracing_subscriber::registry()
                .with(env_filter)
                .with(fmt_layer)
                .init();
            None
        }
    }
}

fn build_tracer_provider(config: &Config, endpoint: &str) -> Result<SdkTracerProvider, String> {
    let exporter = opentelemetry_otlp::SpanExporter::builder()
        .with_http()
        .with_endpoint(endpoint)
        .with_protocol(Protocol::HttpBinary)
        .with_timeout(Duration::from_secs(3))
        .build()
        .map_err(|error| format!("failed to build OTLP exporter: {error}"))?;

    let resource = Resource::builder_empty()
        .with_attributes([
            KeyValue::new("service.name", config.otel_service_name.clone()),
            KeyValue::new("service.namespace", "kura"),
            KeyValue::new("service.version", env!("CARGO_PKG_VERSION")),
            KeyValue::new(
                "deployment.environment.name",
                config.otel_deployment_environment.clone(),
            ),
            KeyValue::new("kura.region", config.region.clone()),
            KeyValue::new("kura.tenant_id", config.tenant_id.clone()),
            KeyValue::new("service.instance.id", config.node_url.clone()),
        ])
        .build();

    Ok(SdkTracerProvider::builder()
        .with_sampler(Sampler::ParentBased(Box::new(Sampler::TraceIdRatioBased(
            1.0,
        ))))
        .with_resource(resource)
        .with_batch_exporter(exporter)
        .build())
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
    if let Err(error) = span.set_parent(extract_parent_context(headers)) {
        warn!("failed to attach propagated trace context: {error:?}");
    }
}
