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
use sentry::{ClientInitGuard, ClientOptions};
use tracing::{Span, warn};
use tracing_opentelemetry::OpenTelemetrySpanExt;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use crate::config::Config;

pub struct TelemetryGuards {
    tracer_provider: Option<SdkTracerProvider>,
    sentry_guard: Option<ClientInitGuard>,
}

impl TelemetryGuards {
    pub fn shutdown(self) {
        if let Some(provider) = self.tracer_provider
            && let Err(error) = provider.shutdown()
        {
            eprintln!("failed to shutdown OTLP tracer provider: {error}");
        }

        drop(self.sentry_guard);
    }
}

pub fn init_tracing(config: &Config) -> TelemetryGuards {
    global::set_text_map_propagator(TraceContextPropagator::new());

    let env_filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| "kura=info".into());
    let fmt_layer = tracing_subscriber::fmt::layer();
    let sentry_guard = init_sentry(config);

    let tracer_result = match config.otlp_traces_endpoint.as_deref() {
        Some(endpoint) => build_tracer_provider(config, endpoint),
        None => Err("OTLP tracing disabled (no endpoint configured)".to_owned()),
    };

    match tracer_result {
        Ok(tracer_provider) => {
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
            TelemetryGuards {
                tracer_provider: Some(tracer_provider),
                sentry_guard,
            }
        }
        Err(error) => {
            // Reached either when the operator explicitly disabled OTLP
            // (no endpoint configured) or when exporter init genuinely
            // failed. One log line on startup either way; never per-batch.
            eprintln!("OTLP tracing not active: {error}");
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
            TelemetryGuards {
                tracer_provider: None,
                sentry_guard,
            }
        }
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
        release: Some(format!("{}@{}", env!("CARGO_PKG_NAME"), env!("CARGO_PKG_VERSION")).into()),
        server_name: Some(config.otel_service_name.clone().into()),
        ..Default::default()
    }))
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
