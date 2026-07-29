{{- define "pomerium.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "pomerium.labels" -}}
app.kubernetes.io/name: pomerium
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
tuist.dev/env: {{ .Values.tuistEnv }}
{{- end -}}

{{- define "pomerium.selectorLabels" -}}
app.kubernetes.io/name: pomerium
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "pomerium.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "pomerium.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}
