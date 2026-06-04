{{- define "swift-registry.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "swift-registry.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "swift-registry.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "swift-registry.labels" -}}
app.kubernetes.io/name: {{ include "swift-registry.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- range $key, $value := .Values.global.commonLabels }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{- define "swift-registry.selectorLabels" -}}
app.kubernetes.io/name: {{ include "swift-registry.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "swift-registry.componentLabels" -}}
{{ include "swift-registry.selectorLabels" . }}
app.kubernetes.io/component: app
{{- end -}}

{{- define "swift-registry.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
  {{- default (include "swift-registry.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
  {{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "swift-registry.podScheduling" -}}
{{- with .Values.global.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{- define "swift-registry.appSecretName" -}}
{{- printf "%s-app" (include "swift-registry.fullname" .) -}}
{{- end -}}

{{- define "swift-registry.runtimeSecretName" -}}
{{- default (printf "%s-runtime" (include "swift-registry.fullname" .)) .Values.runtimeSecrets.secretName -}}
{{- end -}}

{{- define "swift-registry.dataClaimName" -}}
{{- if .Values.persistence.data.existingClaim -}}
{{- .Values.persistence.data.existingClaim -}}
{{- else if .Values.persistence.data.create -}}
{{- printf "%s-data" (include "swift-registry.fullname" .) -}}
{{- else -}}
{{- fail "persistence.data.existingClaim is required when persistence.data.create is false" -}}
{{- end -}}
{{- end -}}

{{- define "swift-registry.storageClaimName" -}}
{{- if .Values.persistence.storage.existingClaim -}}
{{- .Values.persistence.storage.existingClaim -}}
{{- else if .Values.persistence.storage.create -}}
{{- printf "%s-storage" (include "swift-registry.fullname" .) -}}
{{- else -}}
{{- fail "persistence.storage.existingClaim is required when persistence.storage.create is false" -}}
{{- end -}}
{{- end -}}
