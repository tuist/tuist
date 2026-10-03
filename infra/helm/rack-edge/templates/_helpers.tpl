{{- define "rack-edge.site" -}}
{{- $site := required "site is required: the rack whose edge node this runs on" .Values.site -}}
{{- if not (.Files.Get (printf "sites/%s/mgmt-path.sh" $site)) -}}
{{- fail (printf "sites/%s/ has no rendered files; run 'mise run rack:fleet render' with RACK_SITE=%s" $site $site) -}}
{{- end -}}
{{- $site -}}
{{- end }}

{{- define "rack-edge.labels" -}}
app.kubernetes.io/name: rack-edge
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
tuist.dev/rack-edge: {{ include "rack-edge.site" . }}
{{- end }}
