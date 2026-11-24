{{- define "luft-server.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "luft-server.selectorLabels" -}}
app.kubernetes.io/name: luft-server
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "luft-server.labels" -}}
{{ include "luft-server.selectorLabels" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
tuist.dev/service: luft-server
{{- end -}}

{{- define "luft-server.pgClusterName" -}}
{{ include "luft-server.fullname" . }}-pg
{{- end -}}

{{- define "luft-server.secretName" -}}
{{ include "luft-server.fullname" . }}-runtime
{{- end -}}
