{{/* k8s-monitoring 4.0.3 uses .receiver here, but exporter.loki exposes .input.
Keep the custom WAL writer compatible with applicationObservability's OTLP logs. */}}
{{- define "destinations.custom.alloy.otlp.logs.target" -}}
{{- if eq .destination.ecosystem "loki" -}}
  otelcol.exporter.loki.{{ include "helper.alloy_name" .destinationName }}.input
{{- else if eq .destination.ecosystem "otlp" -}}
  {{- .destination.logs.target -}}
{{- end -}}
{{- end -}}
