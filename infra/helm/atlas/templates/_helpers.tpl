{{- define "atlas.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "atlas.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "atlas.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "atlas.labels" -}}
app.kubernetes.io/name: {{ include "atlas.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "atlas.selectorLabels" -}}
app.kubernetes.io/name: {{ include "atlas.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "atlas.webLabels" -}}
{{ include "atlas.labels" . }}
app.kubernetes.io/component: web
{{- end -}}

{{- define "atlas.webSelectorLabels" -}}
{{ include "atlas.selectorLabels" . }}
app.kubernetes.io/component: web
{{- end -}}

{{- define "atlas.appSecretName" -}}
{{ include "atlas.fullname" . }}-app
{{- end -}}

{{- define "atlas.postgresClusterName" -}}
{{ include "atlas.fullname" . }}-postgres
{{- end -}}

{{- /* CNPG generates `<cluster>-app` with credentials for the app user. */ -}}
{{- define "atlas.postgresAppSecret" -}}
{{ include "atlas.postgresClusterName" . }}-app
{{- end -}}

{{- define "atlas.vectorName" -}}
{{ include "atlas.fullname" . }}-vector
{{- end -}}

{{- define "atlas.vectorSecretName" -}}
{{ include "atlas.vectorName" . }}-storage
{{- end -}}

{{- define "atlas.vectorLabels" -}}
{{ include "atlas.labels" . }}
app.kubernetes.io/component: vector
{{- end -}}

{{- define "atlas.vectorSelectorLabels" -}}
app.kubernetes.io/name: {{ include "atlas.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: vector
{{- end -}}

{{- define "atlas.clickhouseName" -}}
{{ include "atlas.fullname" . }}-clickhouse
{{- end -}}

{{- define "atlas.clickhouseLabels" -}}
{{ include "atlas.labels" . }}
app.kubernetes.io/component: clickhouse
{{- end -}}

{{- define "atlas.clickhouseSelectorLabels" -}}
{{ include "atlas.selectorLabels" . }}
app.kubernetes.io/component: clickhouse
{{- end -}}

{{- define "atlas.clickhouseEnv" -}}
{{- if .Values.clickhouse.enabled }}
- name: ATLAS_CLICKHOUSE_ENABLED
  value: "true"
- name: ATLAS_CLICKHOUSE_HOST
  value: {{ include "atlas.clickhouseName" . | quote }}
- name: ATLAS_CLICKHOUSE_PORT
  value: {{ .Values.clickhouse.service.httpPort | quote }}
- name: ATLAS_CLICKHOUSE_DATABASE
  value: {{ .Values.clickhouse.database | quote }}
- name: ATLAS_CLICKHOUSE_USERNAME
  value: {{ .Values.clickhouse.username | quote }}
{{- end }}
{{- end -}}
