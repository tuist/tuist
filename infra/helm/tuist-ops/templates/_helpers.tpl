{{/* Standard fullname helper. */}}
{{- define "tuist-ops.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "tuist-ops.labels" -}}
app.kubernetes.io/name: tuist-ops
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "tuist-ops.selectorLabels" -}}
app.kubernetes.io/name: tuist-ops
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "tuist-ops.pgClusterName" -}}
{{ include "tuist-ops.fullname" . }}-pg
{{- end -}}

{{- define "tuist-ops.appSecretName" -}}
{{ include "tuist-ops.fullname" . }}-app
{{- end -}}

{{- define "tuist-ops.runtimeSecretName" -}}
{{ include "tuist-ops.fullname" . }}-runtime
{{- end -}}
