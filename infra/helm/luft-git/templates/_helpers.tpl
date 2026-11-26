{{- define "luft-git.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "luft-git.selectorLabels" -}}
app.kubernetes.io/name: luft-git
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "luft-git.labels" -}}
{{ include "luft-git.selectorLabels" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
tuist.dev/service: luft-git
{{- end -}}
