{{- define "kura.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "kura.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "kura.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "kura.labels" -}}
helm.sh/chart: {{ include "kura.chart" . }}
app.kubernetes.io/name: {{ include "kura.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "kura.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kura.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "kura.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "kura.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "kura.headlessServiceName" -}}
{{- printf "%s-headless" (include "kura.fullname" .) -}}
{{- end -}}

{{- /*
Generates the same-cluster `KURA_PEERS` list from the StatefulSet's
own headless service DNS. Kura's runtime accepts a comma-separated
peer list, so extending this helper with a future `extraSeedPeers`
values field is the one-knob change needed to cross-cluster mesh
(e.g. Hetzner backbone + Scaleway edge); no protocol-level work.
*/ -}}
{{- define "kura.seedPeers" -}}
{{- $full := include "kura.fullname" . -}}
{{- $headless := include "kura.headlessServiceName" . -}}
{{- $ns := .Release.Namespace -}}
{{- $scheme := ternary "https" "http" .Values.peerTls.enabled -}}
{{- $port := int .Values.peerTls.internalPort -}}
{{- range $i, $_ := until (int .Values.replicaCount) -}}
{{- if $i }},{{ end -}}{{ $scheme }}://{{ $full }}-{{ $i }}.{{ $headless }}.{{ $ns }}.svc.cluster.local:{{ $port }}
{{- end -}}
{{- end -}}

{{- define "kura.extensionConfigMapName" -}}
{{- if .Values.extension.existingConfigMap -}}
{{- .Values.extension.existingConfigMap -}}
{{- else -}}
{{- printf "%s-extension" (include "kura.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "kura.peerTlsSecretName" -}}
{{- if .Values.peerTls.secretName -}}
{{- .Values.peerTls.secretName -}}
{{- else -}}
{{- printf "%s-peer-tls" (include "kura.fullname" .) -}}
{{- end -}}
{{- end -}}
