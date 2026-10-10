{{- /*
The fleet name the tuist chart's `tuist.rackLinuxFleetName` gives the same
values, with the tuist release named by `tuistRelease`.
*/ -}}
{{- define "rackNodes.fleetName" -}}
{{- $tuistFullname := .Values.fullnameOverride | default (printf "%s-%s" .Values.tuistRelease (.Values.nameOverride | default "tuist")) | trunc 63 | trimSuffix "-" -}}
{{- .Values.rackLinuxFleet.name | default (printf "%s-rack-linux" $tuistFullname) -}}
{{- end -}}

{{- define "rackNodes.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- range $key, $value := (dig "commonLabels" dict (.Values.global | default dict)) }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{- define "rackNodes.image" -}}
{{ .Values.macosFleet.image.repository }}:{{ .Values.macosFleet.image.tag | default "latest" }}
{{- end -}}
