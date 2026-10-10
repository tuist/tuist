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

{{- /*
The password the edges' VRRP adverts carry. It is generated on the first
install and kept on every upgrade: both edges read the same Secret, and a
new password on one of them alone would leave both masters until the other
restarted. keepalived uses the first eight characters.
*/}}
{{- define "rack-edge.vrrpPassword" -}}
{{- $existing := lookup "v1" "Secret" .Release.Namespace (printf "rack-edge-%s-vrrp" (include "rack-edge.site" .)) }}
{{- if and $existing $existing.data (hasKey $existing.data "password") }}
{{- index $existing.data "password" | b64dec }}
{{- else }}
{{- randAlphaNum 8 }}
{{- end }}
{{- end }}

{{- /*
The rendered site files the edge runs, as ConfigMap data.
*/}}
{{- define "rack-edge.siteFiles" -}}
{{- $site := include "rack-edge.site" . }}
mgmt-path.sh: |
  {{- .Files.Get (printf "sites/%s/mgmt-path.sh" $site) | nindent 2 }}
dnsmasq.conf: |
  {{- .Files.Get (printf "sites/%s/dnsmasq.conf" $site) | nindent 2 }}
dhcp.sh: |
  {{- .Files.Get (printf "sites/%s/dhcp.sh" $site) | nindent 2 }}
dnsmasq-machines.conf: |
  {{- .Files.Get (printf "sites/%s/dnsmasq-machines.conf" $site) | nindent 2 }}
tailnet-routes.sh: |
  {{- .Files.Get (printf "sites/%s/tailnet-routes.sh" $site) | nindent 2 }}
{{- range $path, $_ := .Files.Glob (printf "sites/%s/keepalived-*.conf" $site) }}
{{ base $path }}: |
  {{- $.Files.Get $path | nindent 2 }}
{{- end }}
{{- end }}

{{- /*
What names one configuration of the static pod: the site files and the pod's
manifest with no hash in it yet. Sixteen hex digits, the name of the
configuration's directory on the node. Not the VRRP password, which a first
install generates afresh in every template that asks for it; the installer
keeps the node's copy equal to the Secret instead.
*/}}
{{- define "rack-edge.hash" -}}
{{- $manifest := include "rack-edge.staticPod" (dict "root" . "hash" "") }}
{{- printf "%s\n%s" (include "rack-edge.siteFiles" .) $manifest | sha256sum | trunc 16 }}
{{- end }}
