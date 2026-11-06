{{- define "pulse.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "pulse.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "pulse.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "pulse.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pulse.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "pulse.labels" -}}
helm.sh/chart: {{ include "pulse.chart" . }}
{{ include "pulse.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "pulse.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pulse.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "pulse.secretName" -}}
{{- default (include "pulse.fullname" .) .Values.existingSecret }}
{{- end }}

{{/*
Fails rendering early with a readable message instead of letting the release
crash on boot.
*/}}
{{- define "pulse.validate" -}}
{{- if not .Values.storage.bucket }}
{{- fail "storage.bucket is required" }}
{{- end }}
{{- if not .Values.storage.region }}
{{- fail "storage.region is required" }}
{{- end }}
{{- $knownLimits := list "max_records" "max_attributes" "max_key_bytes" "max_value_bytes" "max_attribute_bytes" "max_depth" "max_nodes" "max_trace_nodes" "max_otlp_nodes" }}
{{- range $key, $value := .Values.ingestLimits }}
{{- if not (has $key $knownLimits) }}
{{- fail (printf "ingestLimits: unknown setting %q (expected one of %s)" $key (join ", " $knownLimits)) }}
{{- end }}
{{- $_ := include "pulse.ingestLimitValue" (list $key $value) }}
{{- end }}
{{- include "pulse.validateRetention" . }}
{{- if .Values.ingress.enabled }}
{{- if not .Values.ingress.paths }}
{{- fail "ingress.paths needs at least one path when ingress.enabled is true" }}
{{- end }}
{{- range .Values.ingress.paths }}
{{- if not (hasPrefix "/" (toString .path)) }}
{{- fail (printf "ingress.paths: %q must start with /" (toString .path)) }}
{{- end }}
{{- if not (has .pathType (list "Exact" "Prefix" "ImplementationSpecific")) }}
{{- fail (printf "ingress.paths: pathType for %q must be Exact, Prefix, or ImplementationSpecific" (toString .path)) }}
{{- end }}
{{- end }}
{{- end }}
{{- range $i, $entry := .Values.workloadIdentity.trust }}
{{- if not (and $entry.name $entry.issuer $entry.audiences $entry.keys $entry.bindings) }}
{{- fail (printf "workloadIdentity.trust[%d] needs name, issuer, audiences, keys, and bindings" $i) }}
{{- end }}
{{- if not (has (toString $entry.keys.type) (list "inline" "url")) }}
{{- fail (printf "workloadIdentity.trust[%d].keys.type must be \"inline\" or \"url\"" $i) }}
{{- end }}
{{- if and (eq (toString $entry.keys.type) "url") (not (hasPrefix "https://" (toString $entry.keys.url))) }}
{{- fail (printf "workloadIdentity.trust[%d].keys.url must be an https URL" $i) }}
{{- end }}
{{- if kindIs "map" $entry.keys.jwks }}
{{- range $entry.keys.jwks.keys }}
{{- if not (hasKey . "n") }}
{{- fail (printf "workloadIdentity.trust[%d].keys.jwks: every key needs \"n\" (quote it: YAML reads a bare n as false), or paste the JWKS as a JSON string" $i) }}
{{- end }}
{{- end }}
{{- end }}
{{- range $entry.bindings }}
{{- if not (and .subject .tenant .capabilities) }}
{{- fail (printf "workloadIdentity.trust[%d].bindings need subject, tenant, and capabilities" $i) }}
{{- end }}
{{- end }}
{{- end }}
{{- if not .Values.existingSecret }}
{{- if and (not .Values.tenantTokens) (not .Values.workloadIdentity.trust) (not .Values.tenantRegistry.enabled) (not .Values.issuer) }}
{{- fail "tenantTokens needs at least one tenant unless workloadIdentity.trust, tenantRegistry.enabled or issuer is set (or set existingSecret)" }}
{{- end }}
{{- range .Values.admin.tokenHashes }}
{{- if not (regexMatch "^sha256\\$[0-9a-f]{64}$" (toString .)) }}
{{- fail "admin.tokenHashes entries must be \"sha256$\" followed by 64 lowercase hex characters (digests, not tokens)" }}
{{- end }}
{{- end }}
{{- range $tenant, $digest := .Values.tenantTokens }}
{{- if not (regexMatch "^[A-Za-z0-9_.-]{1,128}$" $tenant) }}
{{- fail (printf "tenantTokens: %q is not a valid tenant name (letters, digits, '_', '.', '-', at most 128)" $tenant) }}
{{- end }}
{{- if not (regexMatch "^sha256\\$[0-9a-f]{64}$" (toString $digest)) }}
{{- fail (printf "tenantTokens.%s must be \"sha256$\" followed by 64 lowercase hex characters (a digest, not the token)" $tenant) }}
{{- end }}
{{- end }}
{{- if or (not .Values.storage.accessKeyId) (not .Values.storage.secretAccessKey) }}
{{- fail "storage.accessKeyId and storage.secretAccessKey are required (or set existingSecret)" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Renders an ingest limit as a decimal string, failing unless it is an integer
in 1..2147483647, the range config/runtime.exs accepts. Values files parse
numbers as floats and --set-string passes strings, so both are handled.
Takes (list key value).
*/}}
{{- define "pulse.ingestLimitValue" -}}
{{- $key := index . 0 }}
{{- $value := index . 1 }}
{{- $n := -1 }}
{{- if kindIs "string" $value }}
{{- if regexMatch "^[0-9]{1,10}$" $value }}
{{- $n = atoi $value }}
{{- end }}
{{- else if kindIs "float64" $value }}
{{- if eq (float64 (int64 $value)) $value }}
{{- $n = int64 $value }}
{{- end }}
{{- else if or (kindIs "int" $value) (kindIs "int64" $value) }}
{{- $n = int64 $value }}
{{- end }}
{{- if or (lt (int64 $n) 1) (gt (int64 $n) 2147483647) }}
{{- fail (printf "ingestLimits.%s must be an integer between 1 and 2147483647, got %v" $key $value) }}
{{- end }}
{{- printf "%d" (int64 $n) }}
{{- end }}

{{/*
Renders an integer setting as a decimal string, failing unless it is a whole
number within the inclusive range config/runtime.exs accepts. Fractions are
rejected rather than truncated. Takes (list name value min max).
*/}}
{{- define "pulse.boundedInteger" -}}
{{- $name := index . 0 }}
{{- $value := index . 1 }}
{{- $min := int64 (index . 2) }}
{{- $max := int64 (index . 3) }}
{{- $n := -1 }}
{{- $valid := false }}
{{- if kindIs "string" $value }}
{{- if regexMatch "^[0-9]{1,10}$" $value }}
{{- $n = atoi $value }}
{{- $valid = true }}
{{- end }}
{{- else if kindIs "float64" $value }}
{{- if eq (float64 (int64 $value)) $value }}
{{- $n = int64 $value }}
{{- $valid = true }}
{{- end }}
{{- else if or (kindIs "int" $value) (kindIs "int64" $value) }}
{{- $n = int64 $value }}
{{- $valid = true }}
{{- end }}
{{- if or (not $valid) (lt (int64 $n) $min) (gt (int64 $n) $max) }}
{{- fail (printf "%s must be an integer between %d and %d, got %v" $name $min $max $value) }}
{{- end }}
{{- printf "%d" (int64 $n) }}
{{- end }}

{{/*
Validates retention values. Called from pulse.validate so rendering fails
before the release would crash on boot.
*/}}
{{- define "pulse.validateRetention" -}}
{{- $r := .Values.retention }}
{{- if not (kindIs "bool" $r.enabled) }}
{{- fail "retention.enabled must be true or false" }}
{{- end }}
{{- if not (has (toString $r.mode) (list "observe" "enforce" "paused")) }}
{{- fail (printf "retention.mode must be observe, enforce, or paused, got %v" $r.mode) }}
{{- end }}
{{- $_ := include "pulse.boundedInteger" (list "retention.logsDays" $r.logsDays 0 3650) }}
{{- $_ := include "pulse.boundedInteger" (list "retention.metricsDays" $r.metricsDays 0 3650) }}
{{- $_ := include "pulse.boundedInteger" (list "retention.tracesDays" $r.tracesDays 0 3650) }}
{{- $_ := include "pulse.boundedInteger" (list "retention.deleteGraceMs" $r.deleteGraceMs 60000 2592000000) }}
{{- $_ := include "pulse.boundedInteger" (list "retention.intervalMs" $r.intervalMs 1000 3600000) }}
{{- $_ := include "pulse.boundedInteger" (list "retention.deleteLimit" $r.deleteLimit 1 512) }}
{{- $_ := include "pulse.boundedInteger" (list "retention.timeoutMs" $r.timeoutMs 1000 600000) }}
{{- $_ := include "pulse.boundedInteger" (list "retention.migrationTimeoutMs" $r.migrationTimeoutMs 30000 3600000) }}
{{- $_ := include "pulse.boundedInteger" (list "retention.futureSkewMs" $r.futureSkewMs 0 86400000) }}
{{- if ne (toString $r.sweepHorizonDays) "" }}
{{- $_ := include "pulse.boundedInteger" (list "retention.sweepHorizonDays" $r.sweepHorizonDays 1 7302) }}
{{- end }}
{{- end }}

{{/*
Pod termination grace. When the retention worker runs (enabled, or either
duration positive) it is raised to cover the pre-stop delay, one full
maintenance operation (or, in enforce mode with a positive duration, one
manifest conversion), and a 15-second drain margin, because stopping a node does not cancel in-flight storage calls.
*/}}
{{- define "pulse.terminationGracePeriodSeconds" -}}
{{- $configured := int64 .Values.terminationGracePeriodSeconds }}
{{- $r := .Values.retention }}
{{- if or $r.enabled (gt (int64 (include "pulse.boundedInteger" (list "retention.logsDays" $r.logsDays 0 3650))) 0) (gt (int64 (include "pulse.boundedInteger" (list "retention.metricsDays" $r.metricsDays 0 3650))) 0) (gt (int64 (include "pulse.boundedInteger" (list "retention.tracesDays" $r.tracesDays 0 3650))) 0) }}
{{- $logsDays := int64 (include "pulse.boundedInteger" (list "retention.logsDays" $r.logsDays 0 3650)) }}
{{- $metricsDays := int64 (include "pulse.boundedInteger" (list "retention.metricsDays" $r.metricsDays 0 3650)) }}
{{- $tracesDays := int64 (include "pulse.boundedInteger" (list "retention.tracesDays" $r.tracesDays 0 3650)) }}
{{- $operationMs := int64 (include "pulse.boundedInteger" (list "retention.timeoutMs" $r.timeoutMs 1000 600000)) }}
{{- if and (eq (toString $r.mode) "enforce") (or (gt $logsDays 0) (gt $metricsDays 0) (gt $tracesDays 0)) }}
{{- $operationMs = max $operationMs (int64 (include "pulse.boundedInteger" (list "retention.migrationTimeoutMs" $r.migrationTimeoutMs 30000 3600000))) }}
{{- end }}
{{- $timeoutSeconds := div (add $operationMs 999) 1000 }}
{{- $required := add $timeoutSeconds (int64 .Values.preStopSleepSeconds) 15 }}
{{- max $configured $required }}
{{- else }}
{{- $configured }}
{{- end }}
{{- end }}

{{/*
Checksum of the deterministic Secret inputs, so pods roll when credentials
change. A generated secret key base is excluded: it never changes once
created, and hashing a second random draw would differ from the stored one.
*/}}
{{- define "pulse.secretChecksum" -}}
{{- dict "secretKeyBase" .Values.secretKeyBase "tenantTokens" .Values.tenantTokens "adminTokenHashes" .Values.admin.tokenHashes "accessKeyId" .Values.storage.accessKeyId "secretAccessKey" .Values.storage.secretAccessKey | toJson | sha256sum }}
{{- end }}

{{/*
Name of a pool's resources: the release fullname for the combined Deployment,
or "<fullname>-<pool>". Takes (list $ pool).
*/}}
{{- define "pulse.poolName" -}}
{{- $root := index . 0 }}
{{- $pool := index . 1 }}
{{- if $pool }}
{{- printf "%s-%s" (include "pulse.fullname" $root) $pool | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- include "pulse.fullname" $root }}
{{- end }}
{{- end }}

{{/*
Whether pods join the Erlang cluster used for rendezvous ownership. Takes
(list $ pool); every pool joins one cluster when clustering is enabled.
*/}}
{{- define "pulse.clustered" -}}
{{- if (index . 0).Values.clustering.enabled }}true{{- end }}
{{- end }}

{{/*
Validated manifest format: paged or flat.
*/}}
{{- define "pulse.manifestFormat" -}}
{{- $format := toString .Values.manifestFormat -}}
{{- if not (has $format (list "paged" "flat")) -}}
{{- fail (printf "manifestFormat must be paged or flat, got %q" $format) -}}
{{- end -}}
{{- $format -}}
{{- end -}}
