{{- define "symptoms.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "symptoms.labels" -}}
app.kubernetes.io/name: symptoms
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "symptoms.selectorLabels" -}}
app.kubernetes.io/name: symptoms
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "symptoms.serviceAccountName" -}}
{{ include "symptoms.fullname" . }}
{{- end -}}

{{- define "symptoms.pgClusterName" -}}
{{ include "symptoms.fullname" . }}-pg
{{- end -}}

{{- define "symptoms.runtimeSecretName" -}}
{{ include "symptoms.fullname" . }}-runtime
{{- end -}}

{{- define "symptoms.environment" -}}
{{- $environment := required "environment is required (staging, canary or production)" .Values.environment -}}
{{- if not (has $environment (list "staging" "canary" "production")) -}}
{{- fail (printf "environment must be staging, canary or production, not %q" $environment) -}}
{{- end -}}
{{- $environment -}}
{{- end -}}
