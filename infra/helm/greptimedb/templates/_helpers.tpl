{{- define "greptimedb.validate" -}}
{{- if ne .Release.Namespace "observability" }}
{{- fail "pilot must be in observability" }}
{{- end }}
{{- if not (has .Values.environment (list "staging" "canary" "production" "management")) }}
{{- fail "GreptimeDB requires an explicit managed environment" }}
{{- end }}
{{- if or (ne .Values.storage.bucket (include "greptimedb.bucket" .)) (ne .Values.storage.prefix "pulse/") }}
{{- fail "GreptimeDB must use the selected environment's isolated pulse/ prefix" }}
{{- end }}
{{- if not (has .Values.topology (list "standalone" "cluster")) }}
{{- fail "GreptimeDB topology must be standalone or cluster" }}
{{- end }}
{{- if and (eq .Values.environment "production") (ne .Values.topology "cluster") }}
{{- fail "production GreptimeDB must use the distributed cluster topology" }}
{{- end }}
{{- if and (eq .Values.environment "management") (or (ne .Values.topology "standalone") (not .Values.persistence.hostPath) (not .Values.nodeSelector)) }}
{{- fail "management Pulse is standalone on a hostPath volume pinned with nodeSelector" }}
{{- end }}
{{- if and (eq .Values.topology "cluster") (or (lt (int .Values.cluster.frontend.replicas) 2) (lt (int .Values.cluster.datanode.replicas) 3)) }}
{{- fail "cluster topology needs at least 2 frontends and 3 datanodes" }}
{{- end }}
{{- end }}

{{- define "greptimedb.bucket" -}}
{{ ternary "tuist-pulse-management" (printf "tuist-pulso-%s" .Values.environment) (eq .Values.environment "management") }}
{{- end }}

{{- define "greptimedb.readerNamespace" -}}
{{- if eq .Values.environment "management" }}observability
{{- else }}{{ ternary "tuist" (printf "tuist-%s" .Values.environment) (eq .Values.environment "production") }}
{{- end }}
{{- end }}

{{- define "greptimedb.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
fsGroup: 1000
seccompProfile:
  type: RuntimeDefault
{{- end }}

{{- define "greptimedb.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: [ALL]
{{- end }}

{{/* Spread replicas of one component across general nodes, never two per host. */}}
{{- define "greptimedb.placement" -}}
nodeSelector:
  node.cluster.x-k8s.io/pool: general
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - topologyKey: kubernetes.io/hostname
        labelSelector:
          matchLabels:
            app.kubernetes.io/instance: pulse
            app.kubernetes.io/component: {{ . }}
{{- end }}

{{/* Combines the pilot and scoped dashboard identities into one passwd file. */}}
{{- define "greptimedb.authInit" -}}
{{- if .Values.dashboard.enabled }}
  - name: combine-auth
    image: busybox:1.37.0
    command: [sh, -ec]
    args:
      - 'umask 077; cat /inputs/pilot /inputs/dashboard > /auth/passwd'
    securityContext:
      {{- include "greptimedb.containerSecurityContext" . | nindent 6 }}
    resources:
      requests: {cpu: 10m, memory: 16Mi}
      limits: {memory: 32Mi}
    volumeMounts:
      - {name: auth-inputs, mountPath: /inputs, readOnly: true}
      - {name: auth, mountPath: /auth}
{{- end }}
{{- end }}

{{- define "greptimedb.authVolumes" -}}
- name: auth
  {{- if .Values.dashboard.enabled }}
  emptyDir: {medium: Memory, sizeLimit: 1Mi}
- name: auth-inputs
  projected:
    defaultMode: 0440
    sources:
      - secret:
          name: pulse-auth
          items: [{key: passwd, path: pilot}]
      - secret:
          name: pulse-dashboard-auth
          items: [{key: passwd, path: dashboard}]
  {{- else }}
  secret: {secretName: pulse-auth, defaultMode: 0440}
  {{- end }}
{{- end }}

{{/* Who may reach the authenticated HTTP API on port 4000. */}}
{{- define "greptimedb.apiIngress" -}}
- from:
    - podSelector: {}
  ports:
    - {port: 4000, protocol: TCP}
{{- if .Values.dashboard.enabled }}
{{- if ne .Values.environment "management" }}
- from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: {{ include "greptimedb.readerNamespace" . }}
      podSelector:
        matchLabels:
          app.kubernetes.io/component: server
  ports:
    - {port: 4000, protocol: TCP}
{{- end }}
- from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: {{ include "greptimedb.readerNamespace" . }}
      podSelector:
        matchLabels:
          {{- if eq .Values.environment "management" }}
          # infra/flux/pulse-pdc: management has no Tuist server or chart.
          app.kubernetes.io/name: pdc-agent
          app.kubernetes.io/instance: pulse
          {{- else }}
          app.kubernetes.io/name: tuist
          app.kubernetes.io/instance: tuist
          {{- end }}
          app.kubernetes.io/component: pdc-agent
  ports:
    - {port: 4000, protocol: TCP}
{{- end }}
{{- end }}

{{- define "greptimedb.logging" -}}
[logging]
level = "info"
log_format = "json"
append_stdout = true
enable_file_logging = false
{{- end }}

{{- define "greptimedb.svc" -}}
{{ . }}.observability.svc.cluster.local
{{- end }}

{{- define "greptimedb.peers" -}}
{{- $name := index . 0 -}}{{- $port := index . 1 -}}
{{- $peers := list -}}
{{- range $i := until 3 -}}
{{- $peers = append $peers (printf "\"%s-%d.%s.observability.svc.cluster.local:%d\"" $name $i $name (int $port)) -}}
{{- end -}}
[{{ join ", " $peers }}]
{{- end }}
