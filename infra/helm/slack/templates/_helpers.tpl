{{- define "slack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "slack.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "slack.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "slack.labels" -}}
app.kubernetes.io/name: {{ include "slack.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- range $key, $value := .Values.global.commonLabels }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{- define "slack.selectorLabels" -}}
app.kubernetes.io/name: {{ include "slack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "slack.componentLabels" -}}
{{ include "slack.selectorLabels" . }}
app.kubernetes.io/component: app
{{- end -}}

{{- define "slack.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
  {{- default (include "slack.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
  {{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "slack.podScheduling" -}}
{{- with .Values.global.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{- define "slack.appSecretName" -}}
{{- printf "%s-app" (include "slack.fullname" .) -}}
{{- end -}}

{{- define "slack.runtimeSecretName" -}}
{{- default (printf "%s-runtime" (include "slack.fullname" .)) .Values.runtimeSecrets.secretName -}}
{{- end -}}

{{- define "slack.dataClaimName" -}}
{{- if .Values.persistence.existingClaim -}}
{{- .Values.persistence.existingClaim -}}
{{- else if .Values.persistence.create -}}
{{- printf "%s-data" (include "slack.fullname" .) -}}
{{- else -}}
{{- fail "persistence.existingClaim is required when persistence.create is false" -}}
{{- end -}}
{{- end -}}
