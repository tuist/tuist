{{- define "tuist.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "tuist.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "tuist.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "tuist.labels" -}}
app.kubernetes.io/name: {{ include "tuist.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- range $key, $value := .Values.global.commonLabels }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{- define "tuist.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tuist.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "tuist.componentLabels" -}}
{{ include "tuist.selectorLabels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "tuist.componentName" -}}
{{ include "tuist.fullname" .root }}-{{ .component }}
{{- end -}}

{{/*
Service account name for an application component.
*/}}
{{- define "tuist.componentServiceAccountName" -}}
{{- $serviceAccount := index .root.Values .component "serviceAccount" -}}
{{- if $serviceAccount.create -}}
  {{- default (printf "%s-%s" (include "tuist.fullname" .root) .component) $serviceAccount.name -}}
{{- else -}}
  {{- default "default" $serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Optional pod spec defaults shared across workloads.
*/}}
{{- define "tuist.podScheduling" -}}
{{- with .Values.global.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.global.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.global.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{- define "tuist.objectStorageEndpoint" -}}
{{- if eq .Values.objectStorage.mode "embedded" -}}
http://{{ include "tuist.componentName" (dict "root" . "component" "object-storage") }}:9000
{{- else -}}
{{- .Values.objectStorage.external.endpoint -}}
{{- end -}}
{{- end -}}

{{- define "tuist.objectStorageAccessKey" -}}
{{- if eq .Values.objectStorage.mode "embedded" -}}
{{- .Values.objectStorage.embedded.rootUser -}}
{{- else -}}
{{- .Values.objectStorage.external.accessKey -}}
{{- end -}}
{{- end -}}

{{- define "tuist.objectStorageSecretKey" -}}
{{- if eq .Values.objectStorage.mode "embedded" -}}
{{- .Values.objectStorage.embedded.rootPassword -}}
{{- else -}}
{{- .Values.objectStorage.external.secretKey -}}
{{- end -}}
{{- end -}}

{{- define "tuist.objectStorageRegion" -}}
{{- if eq .Values.objectStorage.mode "embedded" -}}
{{- .Values.objectStorage.embedded.region -}}
{{- else -}}
{{- .Values.objectStorage.external.region -}}
{{- end -}}
{{- end -}}

{{- define "tuist.objectStorageBucketDefault" -}}
{{- if eq .Values.objectStorage.mode "embedded" -}}
{{- .Values.objectStorage.embedded.buckets.default -}}
{{- else -}}
{{- .Values.objectStorage.external.buckets.default -}}
{{- end -}}
{{- end -}}

{{- define "tuist.objectStorageBucketCache" -}}
{{- if eq .Values.objectStorage.mode "embedded" -}}
{{- .Values.objectStorage.embedded.buckets.cache -}}
{{- else -}}
{{- .Values.objectStorage.external.buckets.cache -}}
{{- end -}}
{{- end -}}

{{- define "tuist.objectStorageBucketXcodeCache" -}}
{{- if eq .Values.objectStorage.mode "embedded" -}}
{{- .Values.objectStorage.embedded.buckets.xcodeCache -}}
{{- else -}}
{{- .Values.objectStorage.external.buckets.xcodeCache -}}
{{- end -}}
{{- end -}}

{{- define "tuist.objectStorageBucketRegistry" -}}
{{- if eq .Values.objectStorage.mode "embedded" -}}
{{- .Values.objectStorage.embedded.buckets.registry -}}
{{- else -}}
{{- .Values.objectStorage.external.buckets.registry -}}
{{- end -}}
{{- end -}}

{{- define "tuist.databaseUrl" -}}
{{- if eq .Values.postgresql.mode "embedded" -}}
ecto://{{ .Values.postgresql.embedded.username }}:{{ .Values.postgresql.embedded.password }}@{{ include "tuist.componentName" (dict "root" . "component" "postgresql") }}:5432/{{ .Values.postgresql.embedded.database }}
{{- else -}}
ecto://{{ .Values.postgresql.external.username }}:{{ .Values.postgresql.external.password }}@{{ .Values.postgresql.external.host }}:{{ .Values.postgresql.external.port }}/{{ .Values.postgresql.external.database }}
{{- end -}}
{{- end -}}

{{- define "tuist.databaseHost" -}}
{{- if eq .Values.postgresql.mode "embedded" -}}
{{ include "tuist.componentName" (dict "root" . "component" "postgresql") }}
{{- else -}}
{{- .Values.postgresql.external.host -}}
{{- end -}}
{{- end -}}

{{- define "tuist.databasePort" -}}
{{- if eq .Values.postgresql.mode "embedded" -}}
5432
{{- else -}}
{{- .Values.postgresql.external.port -}}
{{- end -}}
{{- end -}}

{{- define "tuist.databaseName" -}}
{{- if eq .Values.postgresql.mode "embedded" -}}
{{- .Values.postgresql.embedded.database -}}
{{- else -}}
{{- .Values.postgresql.external.database -}}
{{- end -}}
{{- end -}}

{{- define "tuist.databaseUsername" -}}
{{- if eq .Values.postgresql.mode "embedded" -}}
{{- .Values.postgresql.embedded.username -}}
{{- else -}}
{{- .Values.postgresql.external.username -}}
{{- end -}}
{{- end -}}

{{- define "tuist.clickhouseUrl" -}}
{{- if eq .Values.clickhouse.mode "embedded" -}}
http://{{ include "tuist.componentName" (dict "root" . "component" "clickhouse") }}:8123/{{ .Values.clickhouse.embedded.database }}
{{- else -}}
{{- .Values.clickhouse.external.url -}}
{{- end -}}
{{- end -}}

{{- define "tuist.clickhouseReadyUrl" -}}
{{- if eq .Values.clickhouse.mode "embedded" -}}
http://{{ include "tuist.componentName" (dict "root" . "component" "clickhouse") }}:8123/ping
{{- else -}}
{{- .Values.clickhouse.external.url -}}
{{- end -}}
{{- end -}}

{{- define "tuist.redisUrl" -}}
{{- if eq .Values.redis.mode "embedded" -}}
redis://{{ include "tuist.componentName" (dict "root" . "component" "redis") }}:6379
{{- else -}}
{{- .Values.redis.external.url -}}
{{- end -}}
{{- end -}}

{{- define "tuist.observabilityOtlpEndpoint" -}}
{{- if .Values.observability.enabled -}}
http://{{ include "tuist.componentName" (dict "root" . "component" "otel-collector") }}:4317
{{- end -}}
{{- end -}}

{{/*
License env vars. Resolves to (in order):
  1. ESO-managed Secret (server.externalSecrets.license.item set) — preview /
     managed envs that sync the license from 1Password. Mirrors the MASTER_KEY
     flow in templates/external-secrets.yaml.
  2. Chart-managed app-secrets Secret — when server.license.key is inlined.
*/}}
{{- define "tuist.licenseEnv" -}}
{{- $appSecret := include "tuist.componentName" (dict "root" . "component" "app-secrets") -}}
{{- $esoSecret := include "tuist.componentName" (dict "root" . "component" "server-external-secrets") -}}
{{- $useEso := ne (.Values.server.externalSecrets.license.item | default "") "" -}}
{{- if and $useEso .Values.server.license.key -}}
{{- fail "server.externalSecrets.license.item and server.license.key are mutually exclusive — pick one license source." -}}
{{- end -}}
{{- if or $useEso .Values.server.license.key }}
- name: TUIST_LICENSE_KEY
  valueFrom:
    secretKeyRef:
      name: {{ ternary $esoSecret $appSecret $useEso | quote }}
      key: server-license-key
{{- end }}
{{- if .Values.server.license.certificateBase64 }}
- name: TUIST_LICENSE_CERTIFICATE_BASE64
  valueFrom:
    secretKeyRef:
      name: {{ $appSecret | quote }}
      key: server-license-certificate-base64
{{- end }}
{{- end -}}

{{- define "tuist.serverHeadlessServiceName" -}}
{{- include "tuist.componentName" (dict "root" . "component" "server-headless") -}}
{{- end -}}
