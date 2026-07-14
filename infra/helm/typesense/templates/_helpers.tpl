{{- define "typesense.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "typesense.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "typesense.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "typesense.labels" -}}
app.kubernetes.io/name: {{ include "typesense.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- range $key, $value := .Values.global.commonLabels }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{- define "typesense.selectorLabels" -}}
app.kubernetes.io/name: {{ include "typesense.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "typesense.componentLabels" -}}
{{ include "typesense.selectorLabels" . }}
app.kubernetes.io/component: search
{{- end -}}

{{- define "typesense.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
  {{- default (include "typesense.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
  {{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "typesense.podScheduling" -}}
{{- with .Values.global.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{- define "typesense.runtimeSecretName" -}}
{{- default (printf "%s-runtime" (include "typesense.fullname" .)) .Values.runtimeSecrets.secretName -}}
{{- end -}}

{{- define "typesense.dataClaimName" -}}
{{- if .Values.persistence.existingClaim -}}
{{- .Values.persistence.existingClaim -}}
{{- else if .Values.persistence.create -}}
{{- printf "%s-data" (include "typesense.fullname" .) -}}
{{- else -}}
{{- fail "persistence.existingClaim is required when persistence.create is false" -}}
{{- end -}}
{{- end -}}
