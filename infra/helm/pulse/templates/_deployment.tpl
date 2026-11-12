{{/*
One Pulse Deployment. Takes (dict "root" $ "pool" <name or ""> "values"
<pool values>). The unnamed pool is the combined Deployment that runs every
role and keeps the original name and selector; named pools add a component.
*/}}
{{- define "pulse.deployment" -}}
{{- $root := .root }}
{{- $pool := .pool }}
{{- $values := .values }}
{{- with $root }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "pulse.poolName" (list $root $pool) }}
  labels:
    {{- include "pulse.labels" . | nindent 4 }}
    {{- if $pool }}
    app.kubernetes.io/component: {{ $pool }}
    {{- end }}
spec:
  {{- if not $values.autoscaling.enabled }}
  replicas: {{ include "pulse.boundedInteger" (list (printf "%s replicas" (default "combined" $pool)) $values.replicas 0 1000) }}
  {{- end }}
  {{- with .Values.strategy }}
  strategy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "pulse.selectorLabels" . | nindent 6 }}
      {{- if $pool }}
      app.kubernetes.io/component: {{ $pool }}
      {{- end }}
  template:
    metadata:
      annotations:
        {{- if not .Values.existingSecret }}
        checksum/secret: {{ include "pulse.secretChecksum" . }}
        {{- end }}
        {{- with .Values.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      labels:
        {{- include "pulse.labels" . | nindent 8 }}
        {{- if $pool }}
        app.kubernetes.io/component: {{ $pool }}
        {{- end }}
        {{- if include "pulse.clustered" (list $root $pool) }}
        pulse.tuist.dev/cluster: "true"
        {{- end }}
        {{- with .Values.podLabels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      serviceAccountName: {{ include "pulse.serviceAccountName" . }}
      automountServiceAccountToken: {{ .Values.serviceAccount.automount }}
      terminationGracePeriodSeconds: {{ include "pulse.terminationGracePeriodSeconds" . }}
      {{- with .Values.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
        - name: pulse
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          {{- with .Values.securityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          ports:
            - name: http
              containerPort: 4000
              protocol: TCP
            {{- if and .Values.otlpGrpc.enabled (ne $pool "query") (ne $pool "maintenance") }}
            - name: otlp-grpc
              containerPort: {{ .Values.otlpGrpc.port }}
              protocol: TCP
            {{- end }}
          env:
            - name: PORT
              value: "4000"
            {{- with $pool }}
            - name: PULSE_ROLES
              value: {{ . | quote }}
            {{- end }}
            {{- if include "pulse.clustered" (list $root $pool) }}
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
            # Erlang distribution for rendezvous ownership among these pods.
            - name: RELEASE_DISTRIBUTION
              value: name
            - name: RELEASE_NODE
              value: pulse@$(POD_IP)
            - name: DNS_CLUSTER_QUERY
              value: {{ printf "%s-cluster.%s.svc.cluster.local" (include "pulse.fullname" .) .Release.Namespace | quote }}
            - name: RELEASE_COOKIE
              valueFrom:
                secretKeyRef:
                  name: {{ include "pulse.secretName" . }}
                  key: RELEASE_COOKIE
            {{- end }}
            # The release writes temporary files under RELEASE_TMP; keep them
            # on the writable scratch volume so the root filesystem can be
            # read-only.
            - name: RELEASE_TMP
              value: /tmp
            - name: ERL_CRASH_DUMP
              value: /tmp/erl_crash.dump
            - name: PULSE_S3_BUCKET
              value: {{ .Values.storage.bucket | quote }}
            - name: PULSE_S3_REGION
              value: {{ .Values.storage.region | quote }}
            {{- with .Values.storage.endpoint }}
            - name: PULSE_S3_ENDPOINT
              value: {{ . | quote }}
            {{- end }}
            - name: PULSE_S3_ALLOW_HTTP
              value: {{ .Values.storage.allowHttp | quote }}
            - name: PULSE_MANIFEST_FORMAT
              value: {{ include "pulse.manifestFormat" . | quote }}
            - name: PULSE_METRICS_COMPACTION_ENABLED
              value: {{ .Values.metricsCompaction.enabled | quote }}
            - name: PULSE_METRICS_FINALIZE_ENABLED
              value: {{ .Values.metricsCompaction.finalize | quote }}
            - name: PULSE_MANIFEST_BACKUP_ENABLED
              value: {{ .Values.manifestBackups.enabled | quote }}
            - name: PULSE_MANIFEST_BACKUP_INTERVAL_MS
              value: {{ .Values.manifestBackups.intervalMs | int64 | quote }}
            {{- if and .Values.otlpGrpc.enabled (ne $pool "query") (ne $pool "maintenance") }}
            - name: PULSE_OTLP_GRPC_PORT
              value: {{ .Values.otlpGrpc.port | int64 | quote }}
            - name: PULSE_OTLP_GRPC_MAX_MESSAGE_BYTES
              value: {{ .Values.otlpGrpc.maxMessageBytes | int64 | quote }}
            - name: PULSE_OTLP_GRPC_MAX_IN_FLIGHT
              value: {{ .Values.otlpGrpc.maxInFlight | int64 | quote }}
            {{- end }}
            - name: PULSE_TEMPO_SEARCH_ENABLED
              value: {{ .Values.tempoSearch.enabled | quote }}
            - name: PULSE_TRACE_SEARCH_CONTEXT_HORIZON_MS
              value: {{ include "pulse.boundedInteger" (list "tempoSearch.contextHorizonMs" .Values.tempoSearch.contextHorizonMs 0 604800000) | quote }}
            - name: PULSE_METRICS_FOOTER_PRUNING_ENABLED
              value: {{ .Values.metricsFooterPruning.enabled | quote }}
            - name: PULSE_OBJECT_CACHE_MEMORY_MB
              value: {{ include "pulse.boundedInteger" (list "objectCache.memoryMb" .Values.objectCache.memoryMb 0 1048576) | quote }}
            {{- if .Values.objectCache.disk.enabled }}
            - name: PULSE_OBJECT_CACHE_DIR
              value: /var/cache/pulse/objects
            - name: PULSE_OBJECT_CACHE_DISK_MB
              value: {{ include "pulse.boundedInteger" (list "objectCache.disk.sizeMb" .Values.objectCache.disk.sizeMb 1 104857600) | quote }}
            {{- end }}
            - name: PULSE_TRACE_COMPACTION_ENABLED
              value: {{ .Values.traceCompaction.enabled | quote }}
            - name: PULSE_LOG_COMPACTION_ENABLED
              value: {{ .Values.logCompaction.enabled | quote }}
            - name: PULSE_LOG_ROLLUPS_ENABLED
              value: {{ .Values.logCompaction.rollups | quote }}
            - name: PULSE_LOG_STREAM_GROUPING_ENABLED
              value: {{ .Values.logCompaction.groupByStream | quote }}
            - name: PULSE_SENTRY_PROJECTS_JSON
              value: {{ .Values.sentry.projects | toJson | quote }}
            - name: PULSE_ERROR_PROJECTION_ENABLED
              value: {{ .Values.sentry.projectionEnabled | quote }}
            - name: PULSE_ERROR_HISTORY_DAYS
              value: {{ include "pulse.boundedInteger" (list "sentry.historyDays" .Values.sentry.historyDays 1 365) | quote }}
            - name: PULSE_ERROR_PROJECTION_INTERVAL_MS
              value: {{ include "pulse.boundedInteger" (list "sentry.projectionIntervalMs" .Values.sentry.projectionIntervalMs 1000 60000) | quote }}
            - name: PULSE_RELIABILITY_ENABLED
              value: {{ .Values.reliability.enabled | quote }}
            - name: PULSE_RELIABILITY_TENANTS_JSON
              value: {{ .Values.reliability.tenants | toJson | quote }}
            - name: PULSE_RELIABILITY_PRICE_VALID_UNTIL
              value: {{ .Values.reliability.priceValidUntil | quote }}
            - name: PULSE_RELIABILITY_INPUT_NANO_USD_PER_TOKEN
              value: {{ include "pulse.boundedInteger" (list "reliability.inputNanoUsdPerToken" .Values.reliability.inputNanoUsdPerToken 1 1000000) | quote }}
            - name: PULSE_RELIABILITY_ASSESSMENT_BUDGET_USD
              value: {{ include "pulse.boundedInteger" (list "reliability.assessmentBudgetUsd" .Values.reliability.assessmentBudgetUsd 0 100000) | quote }}
            - name: PULSE_RELIABILITY_OBJECT_BUDGET_USD
              value: {{ include "pulse.boundedInteger" (list "reliability.objectBudgetUsd" .Values.reliability.objectBudgetUsd 0 100000) | quote }}
            - name: PULSE_RELIABILITY_INVESTIGATION_BUDGET_USD
              value: {{ include "pulse.boundedInteger" (list "reliability.investigationBudgetUsd" .Values.reliability.investigationBudgetUsd 0 100000) | quote }}
            - name: PULSE_RELIABILITY_INVESTIGATION_URL
              value: {{ .Values.reliability.investigationUrl | quote }}
            - name: PULSE_ALERTING_EVALUATION_ENABLED
              value: {{ .Values.alerting.evaluationEnabled | quote }}
            - name: PULSE_ALERTING_NOTIFICATIONS_ENABLED
              value: {{ .Values.alerting.notificationsEnabled | quote }}
            - name: PULSE_ALERTING_SOURCE_BINDINGS_JSON
              value: {{ .Values.alerting.sourceBindings | toJson | quote }}
            - name: PULSE_ALERTING_NOTIFICATION_TARGETS_JSON
              value: {{ .Values.alerting.notificationTargets | toJson | quote }}
            - name: PULSE_ALERTING_POLL_INTERVAL_MS
              value: {{ .Values.alerting.pollIntervalMs | quote }}
            - name: PULSE_ALERTING_PRINCIPALS_JSON
              value: {{ .Values.alerting.principals | toJson | quote }}
            - name: PULSE_WORKLOAD_IDENTITY_JSON
              value: {{ .Values.workloadIdentity.trust | toJson | quote }}
            {{- if .Values.issuer }}
            - name: PULSE_ISSUER_JSON
              value: {{ .Values.issuer | toJson | quote }}
            {{- end }}
            {{- with .Values.tenantLimits }}
            - name: PULSE_TENANT_LIMITS_JSON
              value: {{ . | toJson | quote }}
            {{- end }}
            - name: PULSE_TENANT_REGISTRY_ENABLED
              value: {{ .Values.tenantRegistry.enabled | quote }}
            - name: PULSE_TENANT_REGISTRY_CACHE_TTL_MS
              value: {{ include "pulse.boundedInteger" (list "tenantRegistry.cacheTtlMs" .Values.tenantRegistry.cacheTtlMs 1000 300000) | quote }}
            - name: PULSE_TENANT_DELETION_GRACE_MS
              value: {{ include "pulse.boundedInteger" (list "tenantRegistry.deletionGraceMs" .Values.tenantRegistry.deletionGraceMs 60000 2592000000) | quote }}
            - name: PULSE_USAGE_ENABLED
              value: {{ .Values.usage.enabled | quote }}
            - name: PULSE_USAGE_FLUSH_INTERVAL_MS
              value: {{ include "pulse.boundedInteger" (list "usage.flushIntervalMs" .Values.usage.flushIntervalMs 1000 3600000) | quote }}
            - name: PULSE_INGEST_FLUSH_INTERVAL_MS
              value: {{ .Values.ingestBatching.flushIntervalMs | quote }}
            {{- if ne (toString .Values.ingestBatching.maxConcurrentRequests) "" }}
            - name: PULSE_INGEST_MAX_CONCURRENT_REQUESTS
              value: {{ include "pulse.boundedInteger" (list "ingestBatching.maxConcurrentRequests" .Values.ingestBatching.maxConcurrentRequests 1 100000) | quote }}
            {{- end }}
            - name: PULSE_INGEST_RESERVED_REQUESTS_PER_SIGNAL
              value: {{ .Values.ingestBatching.reservedRequestsPerSignal | quote }}
            - name: PULSE_INGEST_MAX_PENDING_BYTES
              value: {{ .Values.ingestBatching.maxPendingBytes | int64 | quote }}
            - name: PULSE_RETENTION_ENABLED
              value: {{ .Values.retention.enabled | quote }}
            - name: PULSE_LOGS_RETENTION_DAYS
              value: {{ include "pulse.boundedInteger" (list "retention.logsDays" .Values.retention.logsDays 0 3650) | quote }}
            - name: PULSE_METRICS_RETENTION_DAYS
              value: {{ include "pulse.boundedInteger" (list "retention.metricsDays" .Values.retention.metricsDays 0 3650) | quote }}
            - name: PULSE_TRACES_RETENTION_DAYS
              value: {{ include "pulse.boundedInteger" (list "retention.tracesDays" .Values.retention.tracesDays 0 3650) | quote }}
            - name: PULSE_RETENTION_MODE
              value: {{ .Values.retention.mode | quote }}
            - name: PULSE_RETENTION_MANIFEST_FORMAT
              value: {{ .Values.retention.manifestFormat | default "paged" | quote }}
            - name: PULSE_RETENTION_DELETE_GRACE_MS
              value: {{ include "pulse.boundedInteger" (list "retention.deleteGraceMs" .Values.retention.deleteGraceMs 60000 2592000000) | quote }}
            - name: PULSE_RETENTION_INTERVAL_MS
              value: {{ include "pulse.boundedInteger" (list "retention.intervalMs" .Values.retention.intervalMs 1000 3600000) | quote }}
            - name: PULSE_RETENTION_DELETE_LIMIT
              value: {{ include "pulse.boundedInteger" (list "retention.deleteLimit" .Values.retention.deleteLimit 1 512) | quote }}
            - name: PULSE_RETENTION_TIMEOUT_MS
              value: {{ include "pulse.boundedInteger" (list "retention.timeoutMs" .Values.retention.timeoutMs 1000 600000) | quote }}
            - name: PULSE_RETENTION_MIGRATION_TIMEOUT_MS
              value: {{ include "pulse.boundedInteger" (list "retention.migrationTimeoutMs" .Values.retention.migrationTimeoutMs 30000 3600000) | quote }}
            - name: PULSE_RETENTION_FUTURE_SKEW_MS
              value: {{ include "pulse.boundedInteger" (list "retention.futureSkewMs" .Values.retention.futureSkewMs 0 86400000) | quote }}
            {{- if ne (toString .Values.retention.sweepHorizonDays) "" }}
            - name: PULSE_RETENTION_SWEEP_HORIZON_DAYS
              value: {{ include "pulse.boundedInteger" (list "retention.sweepHorizonDays" .Values.retention.sweepHorizonDays 1 7302) | quote }}
            {{- end }}
            {{- with .Values.mcp.allowedOrigins }}
            - name: PULSE_MCP_ALLOWED_ORIGINS
              value: {{ join "," . | quote }}
            {{- end }}
            {{- range $key, $value := .Values.ingestLimits }}
            - name: {{ printf "PULSE_INGEST_%s" (upper $key) }}
              value: {{ include "pulse.ingestLimitValue" (list $key $value) | quote }}
            {{- end }}
            {{- range $key := list "SECRET_KEY_BASE" "PULSE_TENANT_TOKENS" "PULSE_S3_ACCESS_KEY_ID" "PULSE_S3_SECRET_ACCESS_KEY" }}
            - name: {{ $key }}
              valueFrom:
                secretKeyRef:
                  name: {{ include "pulse.secretName" $root }}
                  key: {{ $key }}
            {{- end }}
            # Optional, so existing secrets without admin tokens keep working.
            - name: PULSE_ADMIN_TOKENS
              valueFrom:
                secretKeyRef:
                  name: {{ include "pulse.secretName" $root }}
                  key: PULSE_ADMIN_TOKENS
                  optional: true
            {{- with .Values.extraEnv }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
          {{- with .Values.extraEnvFrom }}
          envFrom:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.startupProbe }}
          startupProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.livenessProbe }}
          livenessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.readinessProbe }}
          readinessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- if .Values.preStopSleepSeconds }}
          lifecycle:
            preStop:
              exec:
                command: ["sleep", "{{ .Values.preStopSleepSeconds }}"]
          {{- end }}
          {{- with (default .Values.resources $values.resources) }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            {{- if .Values.objectCache.disk.enabled }}
            - name: object-cache
              mountPath: /var/cache/pulse/objects
            {{- end }}
            {{- if .Values.workloadIdentity.kubernetesApiToken.enabled }}
            - name: kubernetes-api
              mountPath: /var/run/secrets/pulse/kubernetes-api
              readOnly: true
            {{- end }}
      volumes:
        - name: tmp
          emptyDir: {}
        {{- if .Values.objectCache.disk.enabled }}
        - name: object-cache
          emptyDir:
            {{- with .Values.objectCache.disk.medium }}
            medium: {{ . }}
            {{- end }}
            # Headroom over the cache bound for files being written.
            sizeLimit: {{ add (div (mul (int64 .Values.objectCache.disk.sizeMb) 11) 10) 64 }}Mi
        {{- end }}
        {{- if .Values.workloadIdentity.kubernetesApiToken.enabled }}
        - name: kubernetes-api
          projected:
            sources:
              - serviceAccountToken:
                  path: token
                  expirationSeconds: {{ include "pulse.boundedInteger" (list "workloadIdentity.kubernetesApiToken.expirationSeconds" .Values.workloadIdentity.kubernetesApiToken.expirationSeconds 600 86400) }}
              - configMap:
                  name: kube-root-ca.crt
                  items:
                    - key: ca.crt
                      path: ca.crt
        {{- end }}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end }}
{{- end }}
