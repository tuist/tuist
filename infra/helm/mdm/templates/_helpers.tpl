{{- define "mdm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "mdm.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "mdm.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "mdm.labels" -}}
app.kubernetes.io/name: {{ include "mdm.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- range $key, $value := .Values.global.commonLabels }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{- define "mdm.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mdm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "mdm.pgClusterName" -}}
{{- default (printf "%s-pg" (include "mdm.fullname" .)) .Values.postgresql.clusterName -}}
{{- end -}}

{{- /* DATABASE DSN env shared by nanomdm and nanodep containers. CNPG
emits a `<cluster>-app` Secret whose `uri` key is a ready
postgresql:// URL for the bootstrap database/owner. */ -}}
{{- define "mdm.storageDSNEnv" -}}
- name: STORAGE_DSN
  valueFrom:
    secretKeyRef:
      name: {{ include "mdm.pgClusterName" . }}-app
      key: uri
{{- end -}}

{{- define "mdm.podScheduling" -}}
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
{{- end -}}
