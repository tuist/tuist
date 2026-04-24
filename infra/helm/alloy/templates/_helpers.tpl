{{- define "alloy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "alloy.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "alloy.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "alloy.labels" -}}
app.kubernetes.io/name: {{ include "alloy.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "alloy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "alloy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "alloy.secretName" -}}
{{ include "alloy.fullname" . }}-grafana-cloud
{{- end -}}

{{- define "alloy.serviceAccountName" -}}
{{- if .Values.serviceAccount.name -}}
{{- .Values.serviceAccount.name -}}
{{- else -}}
{{ include "alloy.fullname" . }}
{{- end -}}
{{- end -}}

{{- define "alloy.configMapName" -}}
{{ include "alloy.fullname" . }}-config
{{- end -}}
