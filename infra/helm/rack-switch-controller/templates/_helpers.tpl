{{- define "rack-switch-controller.labels" -}}
app.kubernetes.io/name: rack-switch-controller
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "rack-switch-controller.watchNamespace" -}}
{{- required "watchNamespace is required: the namespace holding the rack's RackSwitch objects" .Values.watchNamespace -}}
{{- end }}
