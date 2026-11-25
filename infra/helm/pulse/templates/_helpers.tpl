{{- define "pulse.validate" -}}
{{- if ne .Release.Namespace "observability" }}
{{- fail "pilot must be in observability" }}
{{- end }}
{{- if not (has .Values.environment (list "staging" "canary" "production" "management")) }}
{{- fail "Pulse requires an explicit managed environment" }}
{{- end }}
{{- if or (ne .Values.storage.bucket (include "pulse.bucket" .)) (ne .Values.storage.prefix (include "pulse.prefix" .)) }}
{{- fail "Pulse must use the selected environment's bucket and isolated prefix" }}
{{- end }}
{{- if not (has .Values.topology (list "standalone" "cluster")) }}
{{- fail "Pulse topology must be standalone or cluster" }}
{{- end }}
{{- if and (ne .Values.environment "management") (ne .Values.topology "cluster") }}
{{- fail "workload-cluster Pulse must use the distributed cluster topology" }}
{{- end }}
{{- if not (has .Values.migration.standalone (list "" "serving" "draining")) }}
{{- fail "migration.standalone must be empty, serving or draining" }}
{{- end }}
{{- if and .Values.migration.standalone (not (has .Values.environment (list "staging" "canary"))) }}
{{- fail "only staging and canary migrate from a standalone backend" }}
{{- end }}
{{- if and (eq .Values.environment "management") (or (ne .Values.topology "standalone") (not .Values.persistence.hostPath) (not .Values.nodeSelector)) }}
{{- fail "management Pulse is standalone on a hostPath volume pinned with nodeSelector" }}
{{- end }}
{{- if and (eq .Values.topology "cluster") (or (lt (int .Values.cluster.frontend.replicas) 2) (lt (int .Values.cluster.datanode.replicas) 3)) }}
{{- fail "cluster topology needs at least 2 frontends and 3 datanodes" }}
{{- end }}
{{- end }}

{{/* Management shares production's bucket under its own root, which its
key's IAM policy is limited to; production's Pulse owns pulse/. */}}
{{- define "pulse.bucket" -}}
{{ printf "tuist-pulso-%s" (ternary "production" .Values.environment (eq .Values.environment "management")) }}
{{- end }}

{{/* The standalone StatefulSet's pod, apart from the cluster's pods, for
Service `pulse`. Service selectors take plain labels only. */}}
{{- define "pulse.standaloneSelector" -}}
app.kubernetes.io/instance: pulse
statefulset.kubernetes.io/pod-name: pulse-0
{{- end }}

{{/* The same pod for network policies: the only Pulse pod without a component.
Cilium leaves statefulset.kubernetes.io/pod-name out of a pod's identity, so a
policy selecting it never matches and the pod falls back to pulse-internal. */}}
{{- define "pulse.standalonePolicySelector" -}}
matchLabels:
  app.kubernetes.io/instance: pulse
matchExpressions:
  - {key: app.kubernetes.io/component, operator: DoesNotExist}
{{- end }}

{{- define "pulse.prefix" -}}
{{ ternary "management/" "pulse/" (eq .Values.environment "management") }}
{{- end }}

{{/* Environments whose frontends also speak PostgreSQL on 4003, for Grafana's
PostgreSQL data source (SQL alert rules over logs); only the PDC agent may
reach it. The list lives here rather than in values so adding an environment
changes only that environment's config checksums and restarts. */}}
{{- define "pulse.postgres" -}}
{{- if and (eq .Values.topology "cluster") (has .Values.environment (list "staging" "canary" "production")) }}true{{ end }}
{{- end }}

{{- define "pulse.readerNamespace" -}}
{{- if eq .Values.environment "management" }}observability
{{- else }}{{ ternary "tuist" (printf "tuist-%s" .Values.environment) (eq .Values.environment "production") }}
{{- end }}
{{- end }}

{{- define "pulse.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
fsGroup: 1000
seccompProfile:
  type: RuntimeDefault
{{- end }}

{{- define "pulse.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: [ALL]
{{- end }}

{{/* Spread replicas of one component across general nodes, never two per host. */}}
{{- define "pulse.placement" -}}
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
  {{- if eq . "datanode" }}
    # Server pods burst to their 3-CPU limit. A datanode beside one gets only
    # its request's share when the node saturates, and every log read runs on
    # the datanode leading opentelemetry_logs' one region.
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          topologyKey: kubernetes.io/hostname
          namespaces: [tuist]
          labelSelector:
            matchLabels:
              app.kubernetes.io/instance: tuist
              app.kubernetes.io/component: server
  {{- end }}
{{- end }}

{{/* Combines the pilot and scoped dashboard identities into one passwd file. */}}
{{- define "pulse.authInit" -}}
{{- if .Values.dashboard.enabled }}
  - name: combine-auth
    image: busybox:1.37.0
    command: [sh, -ec]
    args:
      - 'umask 077; cat /inputs/pilot /inputs/dashboard > /auth/passwd'
    securityContext:
      {{- include "pulse.containerSecurityContext" . | nindent 6 }}
    resources:
      requests: {cpu: 10m, memory: 16Mi}
      limits: {memory: 32Mi}
    volumeMounts:
      - {name: auth-inputs, mountPath: /inputs, readOnly: true}
      - {name: auth, mountPath: /auth}
{{- end }}
{{- end }}

{{- define "pulse.authVolumes" -}}
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
{{- define "pulse.apiIngress" -}}
- from:
    - podSelector: {}
  ports:
    - {port: 4000, protocol: TCP}
{{- if .Values.dashboard.enabled }}
{{- if ne .Values.environment "management" }}
- from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: {{ include "pulse.readerNamespace" . }}
      podSelector:
        matchLabels:
          app.kubernetes.io/component: server
  ports:
    - {port: 4000, protocol: TCP}
{{- end }}
- from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: {{ include "pulse.readerNamespace" . }}
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
    {{- if include "pulse.postgres" . }}
    - {port: 4003, protocol: TCP}
    {{- end }}
{{- if ne .Values.environment "management" }}
# Kura, the server's processor and registry sync pods, and the registry post
# their copy of each error to /v1/sentry/ (the tuist chart's sentryPulse).
# The server's web pods already have the rule above; no other producer is
# admitted. hostNetwork Kura pods carry a node's identity and come in through
# pulse-host-ingress.
- from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: {{ include "pulse.readerNamespace" . }}
      podSelector:
        matchExpressions:
          - key: app.kubernetes.io/component
            operator: In
            values: [processor, swift-registry-sync, registry]
  ports:
    - {port: 4000, protocol: TCP}
- from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kura
      podSelector:
        matchLabels:
          app.kubernetes.io/name: kura
  ports:
    - {port: 4000, protocol: TCP}
# The symptoms evaluator (infra/helm/symptoms) reads evidence from the HTTP
# API as its own read-only `symptoms` user (symptomsReader), from its own
# namespace.
- from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: symptoms-{{ .Values.environment }}
      podSelector:
        matchLabels:
          app.kubernetes.io/name: symptoms
          app.kubernetes.io/component: evaluator
  ports:
    - {port: 4000, protocol: TCP}
{{- end }}
{{- end }}
{{- end }}

{{- define "pulse.logging" -}}
[logging]
level = "info"
log_format = "json"
append_stdout = true
enable_file_logging = false
{{- end }}

{{- define "pulse.svc" -}}
{{ . }}.observability.svc.cluster.local
{{- end }}

{{- define "pulse.peers" -}}
{{- $name := index . 0 -}}{{- $port := index . 1 -}}
{{- $peers := list -}}
{{- range $i := until 3 -}}
{{- $peers = append $peers (printf "\"%s-%d.%s.observability.svc.cluster.local:%d\"" $name $i $name (int $port)) -}}
{{- end -}}
[{{ join ", " $peers }}]
{{- end }}

{{/* Each region keeps the WAL topic it was created with, and metasrv keeps
serving every topic it ever created, so changing this only moves new regions. */}}
{{- define "pulse.walTopicPrefix" -}}
pulse_wal_topic
{{- end }}
