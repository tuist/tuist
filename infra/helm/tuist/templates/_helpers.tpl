{{/*
The chart name and the tuist release a resource belongs to. Names and
selector labels derive from both, so infra/helm/xcresult-processor, which
renders this chart's xcresult processor templates in a Helm release of its
own, gives them the names and labels of the tuist release it names in
`tuistRelease`.
*/}}
{{/* Budget outage admission for the serving envelope, not only visible peers.
Include one terminating generation, which may still hold in-flight requests. */}}
{{- define "tuist.rateLimitFallbackReplicas" -}}
{{- $replicas := int .Values.server.replicaCount -}}
{{- if .Values.server.autoscaling.enabled -}}
{{- $replicas = max $replicas (int .Values.server.autoscaling.maxReplicas) -}}
{{- end -}}
{{- $surge := 0 -}}
{{- $strategy := .Values.server.strategy | default dict -}}
{{- if eq ($strategy.type | default "RollingUpdate") "RollingUpdate" -}}
{{- $rollingUpdate := $strategy.rollingUpdate | default dict -}}
{{- $raw := "25%" -}}
{{- if and (hasKey $rollingUpdate "maxSurge") (not (kindIs "invalid" (get $rollingUpdate "maxSurge"))) -}}
{{- $raw = toString (get $rollingUpdate "maxSurge") -}}
{{- end -}}
{{- if regexMatch "^[0-9]+%$" $raw -}}
{{- $surge = int (ceil (divf (mulf $replicas (int (trimSuffix "%" $raw))) 100)) -}}
{{- else if regexMatch "^[0-9]+$" $raw -}}
{{- $surge = int $raw -}}
{{- else -}}
{{- fail "server.strategy.rollingUpdate.maxSurge must be a nonnegative integer or percentage" -}}
{{- end -}}
{{- end -}}
{{- $minimum := max 5 (add (mul 2 $replicas) $surge) -}}
{{- $rawConfigured := toString (.Values.server.rateLimitFallbackReplicas | default 0) -}}
{{- if not (regexMatch "^[0-9]+$" $rawConfigured) -}}
{{- fail "server.rateLimitFallbackReplicas must be zero (automatic) or a positive integer" -}}
{{- end -}}
{{- $configured := int $rawConfigured -}}
{{- if and (gt $configured 0) (lt $configured $minimum) -}}
{{- fail (printf "server.rateLimitFallbackReplicas must cover the serving/rollout envelope (at least %d)" $minimum) -}}
{{- end -}}
{{- max $minimum $configured -}}
{{- end -}}

{{- define "tuist.name" -}}
{{- default "tuist" .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "tuist.releaseName" -}}
{{- if eq .Chart.Name "xcresult-processor" -}}
{{- required "tuistRelease is required: the name of the tuist release whose xcresult processor this release installs" .Values.tuistRelease -}}
{{- else -}}
{{- .Release.Name -}}
{{- end -}}
{{- end -}}

{{- define "tuist.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" (include "tuist.releaseName" .) (include "tuist.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "tuist.labels" -}}
app.kubernetes.io/name: {{ include "tuist.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ include "tuist.releaseName" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- range $key, $value := .Values.global.commonLabels }}
{{ $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{- define "tuist.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tuist.name" . }}
app.kubernetes.io/instance: {{ include "tuist.releaseName" . }}
{{- end -}}

{{/*
Whether this render owns the xcresult processor's Deployment and PDB. With
`xcresultProcessor.ownRelease`, infra/helm/xcresult-processor renders them
and the tuist release leaves them out; otherwise the tuist release renders
them and the processor chart renders nothing.
*/}}
{{- define "tuist.rendersXcresultProcessor" -}}
{{- if and .Values.xcresultProcessor.enabled (eq (.Values.xcresultProcessor.ownRelease | default false) (eq .Chart.Name "xcresult-processor")) -}}
true
{{- end -}}
{{- end -}}

{{- define "tuist.componentLabels" -}}
{{ include "tuist.selectorLabels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "tuist.componentName" -}}
{{ include "tuist.fullname" .root }}-{{ .component }}
{{- end -}}

{{/*
Fully qualified server image reference. server.image.tag is required: the
chart's .Chart.AppVersion pins the chart's own version (bumped alongside
templates), not the server image, which ships on its own 1.x release cadence
under ghcr.io/tuist/tuist. Falling back to AppVersion would render a tag that
does not exist and land the deployment in ImagePullBackOff — this fail is
loud instead. Every deploy pipeline sets the tag via --set at helm-upgrade
time (see .github/workflows/server-deployment.yml); self-hosters must set it
in their values file.
*/}}
{{- define "tuist.serverImage" -}}
{{- $tag := .Values.server.image.tag | default "" -}}
{{- if eq $tag "" -}}
{{- fail "server.image.tag is required. The chart's .Chart.AppVersion does not track the server image (published under ghcr.io/tuist/tuist on a 1.x cadence). Pin an explicit tag, e.g. `server: { image: { tag: \"1.318.0\" } }`, matching a release from https://github.com/tuist/tuist/releases?q=server." -}}
{{- end -}}
{{- printf "%s:%s" .Values.server.image.repository $tag -}}
{{- end -}}

{{/*
Name of the server migration Job. Stable when it runs as a Helm hook, and
scoped to the release revision when it runs as a regular Job, so that Helm
replaces it on upgrade instead of tripping the immutable `spec.template`.
*/}}
{{- define "tuist.serverMigrateJobName" -}}
{{- $base := include "tuist.componentName" (dict "root" . "component" "server-migrate") -}}
{{- if and (not .Values.server.migrationJob.asHook) .Values.server.migrationJob.namePerRevision -}}
{{- printf "%s-r%d" $base (int .Release.Revision) -}}
{{- else -}}
{{- $base -}}
{{- end -}}
{{- end -}}

{{/*
Service account name for an application component.
*/}}
{{- define "tuist.componentServiceAccountName" -}}
{{- $serviceAccount := index .root.Values .component "serviceAccount" -}}
{{- if $serviceAccount.create -}}
  {{- default (printf "%s-%s" (include "tuist.fullname" .root) .component) $serviceAccount.name -}}
{{- else -}}
  {{- default "default" $serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Optional pod spec defaults shared across workloads.
*/}}
{{- define "tuist.podScheduling" -}}
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
{{- end }}

{{/*
Mac mini fleet names. "Fleet" stays as the human-facing label
for "a logical group of identical Mac minis" — CAPI doesn't ship
a Fleet primitive, but the concept is real, and it ties together
every resource that needs to share an identity:

  - the MachineDeployment + MachineSet + Machines that own host
    lifecycle
  - the ScalewayAppleSiliconMachineTemplate the deployment clones
    from
  - the per-fleet SSH-key Secret (`<fleetName>-ssh`)
  - the Node label `tuist.dev/fleet=<name>` and the Pod
    nodeSelector that pins workloads to the right fleet

Centralizing the name in this helper keeps macos-fleet.yaml,
runners-fleet.yaml, and the workload Deployments pinned to the
same value without copy-paste drift.

Defaults pin the existing xcresult fleet to its release-name-
derived value so a chart upgrade doesn't rename Mac minis (which
would otherwise force the operator to re-order hosts under
Scaleway's 24h-floor). Override `macosFleet.name` only on a
green-field cluster.
*/}}
{{- define "tuist.macosFleetName" -}}
{{- .Values.macosFleet.name | default (include "tuist.componentName" (dict "root" . "component" "macos-fleet")) -}}
{{- end -}}

{{- define "tuist.runnersFleetName" -}}
{{- .Values.runnersFleet.name | default (include "tuist.componentName" (dict "root" . "component" "runners-fleet")) -}}
{{- end -}}

{{- define "tuist.rackFleetName" -}}
{{- .Values.rackFleet.name | default (include "tuist.componentName" (dict "root" . "component" "rack-fleet")) -}}
{{- end -}}

{{- define "tuist.rackLinuxFleetName" -}}
{{- .Values.rackLinuxFleet.name | default (include "tuist.componentName" (dict "root" . "component" "rack-linux")) -}}
{{- end -}}

{{- define "tuist.buildersFleetName" -}}
{{- .Values.buildersFleet.name | default (include "tuist.componentName" (dict "root" . "component" "builders-fleet")) -}}
{{- end -}}

{{/*
Linux runner fleet name — the value of the
`node.cluster.x-k8s.io/pool=` label CAPI's label-sync propagates from
the runner MachineDeployment to each runner Node. The chart's Linux
RunnerPool CRs render this as `spec.fleetSelector`; the
runners-controller's podtemplate uses it as the Pod's nodeSelector
on the `node.cluster.x-k8s.io/pool=` key.

Cluster team-managed: the matching entry must exist in
`infra/k8s/clusters/cluster-<env>.yaml` under
`spec.topology.workers.machineDeployments[]` with
`metadata.labels.node.cluster.x-k8s.io/pool: <this value>`.

Defaults to `runners-linux` to match the convention in
`cluster-staging.yaml`. Override via `runnersFleetLinux.name` only
if the cluster topology uses a different pool name.
*/}}
{{- define "tuist.runnersFleetLinuxName" -}}
{{- .Values.runnersFleetLinux.name | default "runners-linux" -}}
{{- end -}}

{{/*
The Secret holding the object-storage credentials, which is not always the
same one. With `managedSecrets` the credentials are synced into their own
Secret by External Secrets and the chart never sees their values; without it
they are rendered into app-secrets from values. `server-deployment.yaml`
branches on this inline; anything else that needs those credentials has to
branch the same way, or it reads a key that exists and is empty.
*/}}
{{- define "tuist.objectStorageCredentialsSecretName" -}}
{{- if and (eq .Values.objectStorage.mode "external") .Values.objectStorage.external.managedSecrets -}}
{{ include "tuist.componentName" (dict "root" . "component" "object-storage-external-secrets") }}
{{- else -}}
{{ include "tuist.componentName" (dict "root" . "component" "app-secrets") }}
{{- end -}}
{{- end -}}

{{- define "tuist.objectStorageEndpoint" -}}
{{- if eq .Values.objectStorage.mode "embedded" -}}
http://{{ include "tuist.componentName" (dict "root" . "component" "object-storage") }}:9000
{{- else -}}
{{- .Values.objectStorage.external.endpoint -}}
{{- end -}}
{{- end -}}

{{- define "tuist.objectStorageAccessKey" -}}
{{- if eq .Values.objectStorage.mode "embedded" -}}
{{- .Values.objectStorage.embedded.rootUser -}}
{{- else -}}
{{- .Values.objectStorage.external.accessKey -}}
{{- end -}}
{{- end -}}

{{- define "tuist.objectStorageSecretKey" -}}
{{- if eq .Values.objectStorage.mode "embedded" -}}
{{- .Values.objectStorage.embedded.rootPassword -}}
{{- else -}}
{{- .Values.objectStorage.external.secretKey -}}
{{- end -}}
{{- end -}}

{{- define "tuist.objectStorageRegion" -}}
{{- if eq .Values.objectStorage.mode "embedded" -}}
{{- .Values.objectStorage.embedded.region -}}
{{- else -}}
{{- .Values.objectStorage.external.region -}}
{{- end -}}
{{- end -}}

{{/*
S3 storage driver env for a CNCF `distribution` registry. Used by the
Docker Hub pull-through cache (registryCache). Kept as a helper rather
than inlined because the credential branching is fiddly and a second
registry component would need exactly the same env.

Call with the component's `s3` values:

  {{- include "tuist.registryStorageEnv" (dict "root" . "s3" .Values.registryCache.s3) | nindent 12 }}
*/}}
{{- define "tuist.registryStorageEnv" -}}
{{- $root := .root -}}
{{- $objectStorageAccessKey := include "tuist.objectStorageAccessKey" $root -}}
{{- $objectStorageSecretKey := include "tuist.objectStorageSecretKey" $root -}}
- name: REGISTRY_STORAGE
  value: s3
- name: REGISTRY_STORAGE_S3_REGION
  value: {{ include "tuist.objectStorageRegion" $root | quote }}
- name: REGISTRY_STORAGE_S3_REGIONENDPOINT
  value: {{ include "tuist.objectStorageEndpoint" $root | quote }}
- name: REGISTRY_STORAGE_S3_FORCEPATHSTYLE
  value: "true"
# Embedded MinIO is plain http (:9000); external object stores
# (Tigris) are https. Drive TLS off the storage mode so the S3
# driver doesn't try to speak TLS to an http endpoint.
- name: REGISTRY_STORAGE_S3_SECURE
  value: {{ ternary "false" "true" (eq $root.Values.objectStorage.mode "embedded") | quote }}
- name: REGISTRY_STORAGE_S3_BUCKET
  value: {{ .s3.bucket | quote }}
- name: REGISTRY_STORAGE_S3_ROOTDIRECTORY
  value: {{ .s3.rootDirectory | quote }}
{{- if and (eq $root.Values.objectStorage.mode "external") $root.Values.objectStorage.external.managedSecrets }}
# Managed envs: the real S3 creds live in the ESO-synced
# object-storage-external-secrets Secret. app-secrets carries
# only the (empty) values-supplied key, so the registry must read
# from here — same branch the server uses.
- name: REGISTRY_STORAGE_S3_ACCESSKEY
  valueFrom:
    secretKeyRef:
      name: {{ include "tuist.componentName" (dict "root" $root "component" "object-storage-external-secrets") }}
      key: object-storage-access-key
- name: REGISTRY_STORAGE_S3_SECRETKEY
  valueFrom:
    secretKeyRef:
      name: {{ include "tuist.componentName" (dict "root" $root "component" "object-storage-external-secrets") }}
      key: object-storage-secret-key
{{- else if and $objectStorageAccessKey $objectStorageSecretKey }}
- name: REGISTRY_STORAGE_S3_ACCESSKEY
  valueFrom:
    secretKeyRef:
      name: {{ include "tuist.componentName" (dict "root" $root "component" "app-secrets") }}
      key: object-storage-access-key
- name: REGISTRY_STORAGE_S3_SECRETKEY
  valueFrom:
    secretKeyRef:
      name: {{ include "tuist.componentName" (dict "root" $root "component" "app-secrets") }}
      key: object-storage-secret-key
{{- end }}
{{- end -}}

{{- define "tuist.objectStorageBucketDefault" -}}
{{- if eq .Values.objectStorage.mode "embedded" -}}
{{- .Values.objectStorage.embedded.buckets.default -}}
{{- else -}}
{{- .Values.objectStorage.external.buckets.default -}}
{{- end -}}
{{- end -}}

{{- define "tuist.objectStorageBucketCache" -}}
{{- if eq .Values.objectStorage.mode "embedded" -}}
{{- .Values.objectStorage.embedded.buckets.cache -}}
{{- else -}}
{{- .Values.objectStorage.external.buckets.cache -}}
{{- end -}}
{{- end -}}

{{- define "tuist.objectStorageBucketXcodeCache" -}}
{{- if eq .Values.objectStorage.mode "embedded" -}}
{{- .Values.objectStorage.embedded.buckets.xcodeCache -}}
{{- else -}}
{{- .Values.objectStorage.external.buckets.xcodeCache -}}
{{- end -}}
{{- end -}}

{{- define "tuist.objectStorageBucketRegistry" -}}
{{- if eq .Values.objectStorage.mode "embedded" -}}
{{- .Values.objectStorage.embedded.buckets.registry -}}
{{- else -}}
{{- .Values.objectStorage.external.buckets.registry -}}
{{- end -}}
{{- end -}}

{{- define "tuist.serverObjectStorageEnv" -}}
- name: TUIST_OBJECT_STORAGE_PROVIDER
  value: {{ .Values.server.storage.provider | quote }}
{{- if eq .Values.server.storage.provider "azure_blob" }}
- name: TUIST_AZURE_STORAGE_ACCOUNT_NAME
  value: {{ .Values.server.azureBlob.accountName | quote }}
- name: TUIST_AZURE_BLOB_CONTAINER_NAME
  value: {{ .Values.server.azureBlob.containerName | quote }}
{{- with .Values.server.azureBlob.endpoint }}
- name: TUIST_AZURE_BLOB_ENDPOINT
  value: {{ . | quote }}
{{- end }}
- name: TUIST_AZURE_BLOB_SERVICE_VERSION
  value: {{ .Values.server.azureBlob.serviceVersion | quote }}
{{- if .Values.server.azureBlob.accountKey }}
- name: TUIST_AZURE_STORAGE_ACCOUNT_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "tuist.componentName" (dict "root" . "component" "app-secrets") }}
      key: azure-blob-account-key
{{- end }}
{{- end }}
{{- end -}}

{{/*
Cache app's DATABASE_URL. The pinned cache image (0.29.x) uses SQLite on the
pod's /data volume and does not consume DATABASE_URL, so the helper returns
empty and the deployment omits the env var. Kept as a helper (rather than
deleting it inline) so a future cache image that reintroduces an external
database only needs to change one composition site.
*/}}
{{- define "tuist.cacheDatabaseUrl" -}}
{{- end -}}

{{/*
CNPG generates `<cluster-name>-app` for the owner / migration role from
`bootstrap.initdb.owner`. Managed runtime roles use the password Secret
names declared in `managed.roles[].passwordSecret.name`.
*/}}
{{- define "tuist.cnpgClusterName" -}}
{{- include "tuist.componentName" (dict "root" . "component" "pg") -}}
{{- end -}}

{{- define "tuist.cnpgAppSecretName" -}}
{{- printf "%s-app" (include "tuist.cnpgClusterName" .) -}}
{{- end -}}

{{- define "tuist.cnpgWebRoleSecretName" -}}
{{- include "tuist.componentName" (dict "root" . "component" "pg-tuist-web") -}}
{{- end -}}

{{- define "tuist.cnpgServiceRW" -}}
{{- printf "%s-rw" (include "tuist.cnpgClusterName" .) -}}
{{- end -}}

{{- define "tuist.cnpgServiceRO" -}}
{{- printf "%s-ro" (include "tuist.cnpgClusterName" .) -}}
{{- end -}}

{{/* CNPG names the Pooler's Service after the Pooler CR's metadata.name. */}}
{{- define "tuist.cnpgServicePooler" -}}
{{- printf "%s-pooler-rw" (include "tuist.cnpgClusterName" .) -}}
{{- end -}}

{{- define "tuist.externalPostgresqlHostEnv" -}}
TUIST_POSTGRESQL_HOST
{{- end -}}

{{- define "tuist.externalPostgresqlUsernameEnv" -}}
TUIST_POSTGRESQL_USERNAME
{{- end -}}

{{- define "tuist.externalPostgresqlPasswordEnv" -}}
TUIST_POSTGRESQL_PASSWORD
{{- end -}}

{{- define "tuist.externalPostgresqlSecretEnv" -}}
{{- if and (eq .Values.postgresql.mode "external") .Values.postgresql.external.existingSecret -}}
{{- $secretName := .Values.postgresql.external.existingSecret -}}
{{- $keys := .Values.postgresql.external.existingSecretKeys | default dict -}}
- name: {{ include "tuist.externalPostgresqlHostEnv" . }}
  valueFrom:
    secretKeyRef:
      name: {{ $secretName | quote }}
      key: {{ required "postgresql.external.existingSecretKeys.host is required when postgresql.external.existingSecret is set" $keys.host | quote }}
- name: {{ include "tuist.externalPostgresqlUsernameEnv" . }}
  valueFrom:
    secretKeyRef:
      name: {{ $secretName | quote }}
      key: {{ required "postgresql.external.existingSecretKeys.username is required when postgresql.external.existingSecret is set" $keys.username | quote }}
- name: {{ include "tuist.externalPostgresqlPasswordEnv" . }}
  valueFrom:
    secretKeyRef:
      name: {{ $secretName | quote }}
      key: {{ required "postgresql.external.existingSecretKeys.password is required when postgresql.external.existingSecret is set" $keys.password | quote }}
{{- end -}}
{{- end -}}

{{- define "tuist.databaseUrl" -}}
{{- if eq .Values.postgresql.mode "embedded" -}}
ecto://{{ .Values.postgresql.embedded.username }}:{{ .Values.postgresql.embedded.password }}@{{ include "tuist.componentName" (dict "root" . "component" "postgresql") }}:5432/{{ .Values.postgresql.embedded.database }}
{{- else if eq .Values.postgresql.mode "external" -}}
{{- if .Values.postgresql.external.existingSecret -}}
ecto://$({{ include "tuist.externalPostgresqlUsernameEnv" . }}):$({{ include "tuist.externalPostgresqlPasswordEnv" . }})@$({{ include "tuist.externalPostgresqlHostEnv" . }}):{{ .Values.postgresql.external.port }}/{{ .Values.postgresql.external.database }}
{{- else -}}
ecto://{{ .Values.postgresql.external.username }}:{{ .Values.postgresql.external.password }}@{{ .Values.postgresql.external.host }}:{{ .Values.postgresql.external.port }}/{{ .Values.postgresql.external.database }}
{{- end -}}
{{- else if eq .Values.postgresql.mode "cnpg" -}}
{{- fail "tuist.databaseUrl is not literal under postgresql.mode=cnpg — wire DATABASE_URL from the CNPG-generated Secret via envFrom or secretKeyRef instead." -}}
{{- end -}}
{{- end -}}

{{- define "tuist.databaseHost" -}}
{{- if eq .Values.postgresql.mode "embedded" -}}
{{ include "tuist.componentName" (dict "root" . "component" "postgresql") }}
{{- else if eq .Values.postgresql.mode "cnpg" -}}
{{ include "tuist.cnpgServiceRW" . }}
{{- else if eq .Values.postgresql.mode "external" -}}
{{- if .Values.postgresql.external.existingSecret -}}
$({{ include "tuist.externalPostgresqlHostEnv" . }})
{{- else -}}
{{- .Values.postgresql.external.host -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "tuist.databasePort" -}}
{{- if eq .Values.postgresql.mode "embedded" -}}
5432
{{- else if eq .Values.postgresql.mode "cnpg" -}}
5432
{{- else -}}
{{- .Values.postgresql.external.port -}}
{{- end -}}
{{- end -}}

{{- define "tuist.databaseName" -}}
{{- if eq .Values.postgresql.mode "embedded" -}}
{{- .Values.postgresql.embedded.database -}}
{{- else if eq .Values.postgresql.mode "cnpg" -}}
{{- .Values.postgresql.cnpg.database -}}
{{- else -}}
{{- .Values.postgresql.external.database -}}
{{- end -}}
{{- end -}}

{{- define "tuist.databaseUsername" -}}
{{- if eq .Values.postgresql.mode "embedded" -}}
{{- .Values.postgresql.embedded.username -}}
{{- else if eq .Values.postgresql.mode "cnpg" -}}
{{- .Values.postgresql.cnpg.owner -}}
{{- else if eq .Values.postgresql.mode "external" -}}
{{- if .Values.postgresql.external.existingSecret -}}
$({{ include "tuist.externalPostgresqlUsernameEnv" . }})
{{- else -}}
{{- .Values.postgresql.external.username -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "tuist.clickhouseUrl" -}}
{{- if eq .Values.clickhouse.mode "embedded" -}}
http://{{ include "tuist.componentName" (dict "root" . "component" "clickhouse") }}:8123/{{ .Values.clickhouse.embedded.database }}
{{- else -}}
{{- .Values.clickhouse.external.url -}}
{{- end -}}
{{- end -}}

{{/*
TUIST_CLICKHOUSE_URL env-var block. Emits a `value:` literal by default, or a
`valueFrom.secretKeyRef` pointing at clickhouse.external.existingSecret when
that field is set — the escape hatch for Vault-synced installs that don't
want ClickHouse credentials rendered into the manifest. Mutually exclusive
with `clickhouse.external.url`. Empty in `managed` mode, where
`tuist.clickhouseManagedEnv` supplies the URL instead.
*/}}
{{- define "tuist.clickhouseUrlEnv" -}}
{{- if ne .Values.clickhouse.mode "managed" -}}
{{- $existingSecret := "" -}}
{{- if eq .Values.clickhouse.mode "external" -}}
{{- $existingSecret = .Values.clickhouse.external.existingSecret | default "" -}}
{{- end -}}
{{- if ne $existingSecret "" -}}
{{- if ne (.Values.clickhouse.external.url | default "") "" -}}
{{- fail "clickhouse.external.existingSecret is mutually exclusive with clickhouse.external.url; pick one source for TUIST_CLICKHOUSE_URL." -}}
{{- end -}}
{{- $key := .Values.clickhouse.external.existingSecretKey | default "" -}}
{{- if eq $key "" -}}
{{- fail "clickhouse.external.existingSecretKey is required when clickhouse.external.existingSecret is set." -}}
{{- end }}
- name: TUIST_CLICKHOUSE_URL
  valueFrom:
    secretKeyRef:
      name: {{ $existingSecret | quote }}
      key: {{ $key | quote }}
{{- else }}
- name: TUIST_CLICKHOUSE_URL
  value: {{ include "tuist.clickhouseUrl" . | quote }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
TUIST_SECRET_KEY_BASE env-var block. Points at the chart-managed app-secrets
Secret by default, or at server.secretKeyBaseExistingSecret when that field
is set — the escape hatch for Vault-synced installs. Mutually exclusive with
`server.secretKeyBase`.
*/}}
{{- define "tuist.secretKeyBaseEnv" -}}
{{- $existingSecret := .Values.server.secretKeyBaseExistingSecret | default "" -}}
{{- if ne $existingSecret "" -}}
{{- if ne (.Values.server.secretKeyBase | default "") "" -}}
{{- fail "server.secretKeyBaseExistingSecret is mutually exclusive with server.secretKeyBase; pick one source for TUIST_SECRET_KEY_BASE." -}}
{{- end -}}
{{- $key := .Values.server.secretKeyBaseExistingSecretKey | default "" -}}
{{- if eq $key "" -}}
{{- fail "server.secretKeyBaseExistingSecretKey is required when server.secretKeyBaseExistingSecret is set." -}}
{{- end }}
- name: TUIST_SECRET_KEY_BASE
  valueFrom:
    secretKeyRef:
      name: {{ $existingSecret | quote }}
      key: {{ $key | quote }}
{{- else }}
- name: TUIST_SECRET_KEY_BASE
  valueFrom:
    secretKeyRef:
      name: {{ include "tuist.componentName" (dict "root" . "component" "app-secrets") | quote }}
      key: server-secret-key-base
{{- end -}}
{{- end -}}

{{- define "tuist.clickhouseReadyUrl" -}}
{{- if or (eq .Values.clickhouse.mode "embedded") (eq .Values.clickhouse.mode "managed") -}}
http://{{ include "tuist.componentName" (dict "root" . "component" "clickhouse") }}:8123/ping
{{- else if .Values.clickhouse.external.pingUrl -}}
{{- .Values.clickhouse.external.pingUrl -}}
{{- else -}}
{{- .Values.clickhouse.external.url -}}
{{- end -}}
{{- end -}}

{{- define "tuist.redisUrl" -}}
{{- if eq .Values.redis.mode "embedded" -}}
redis://{{ include "tuist.componentName" (dict "root" . "component" "redis") }}:6379
{{- else -}}
{{- .Values.redis.external.url -}}
{{- end -}}
{{- end -}}

{{- define "tuist.observabilityOtlpEndpoint" -}}
{{- if .Values.observability.enabled -}}
http://{{ include "tuist.componentName" (dict "root" . "component" "otel-collector") }}:4317
{{- end -}}
{{- end -}}

{{/*
Kura OAuth introspection client env vars. The values are sourced from
one of:

  1. An explicitly named Secret in this release's namespace when
     server.kuraIntrospection.secretName is set.

  2. The kura-shared-secrets Secret in this release's namespace when this
     release installs the kuraController (managed envs: one release runs
     both server and controller in their respective namespaces, the
     chart mirrors the Secret into the server namespace).

  3. The kura-shared-secrets Secret in this release's namespace when
     server.kuraIntrospection.useSharedSecret is true (preview envs:
     the kuraController is installed once at platform level into the
     `kura` namespace, and the deploy workflow copies the Secret into
     this release's namespace before installing the chart).

  4. The server-external-secrets ESO Secret when
     server.externalSecrets.kuraIntrospection.item is set.

*/}}
{{- define "tuist.kuraIntrospectionEnv" -}}
{{- $esoSecret := include "tuist.componentName" (dict "root" . "component" "server-external-secrets") -}}
{{- $kuraSharedSecret := "kura-shared-secrets" -}}
{{- $explicitSecret := .Values.server.kuraIntrospection.secretName | default "" -}}
{{- $useShared := or (and .Values.kuraController.enabled .Values.kuraController.sharedSecrets.enabled .Values.kuraController.sharedSecrets.kuraIntrospection.enabled) .Values.server.kuraIntrospection.useSharedSecret -}}
{{- if ne $explicitSecret "" }}
- name: KURA_CONTROL_PLANE_CLIENT_ID
  valueFrom:
    secretKeyRef:
      name: {{ $explicitSecret | quote }}
      key: KURA_CONTROL_PLANE_CLIENT_ID
- name: KURA_CONTROL_PLANE_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ $explicitSecret | quote }}
      key: KURA_CONTROL_PLANE_CLIENT_SECRET
{{- else if $useShared }}
- name: KURA_CONTROL_PLANE_CLIENT_ID
  valueFrom:
    secretKeyRef:
      name: {{ $kuraSharedSecret | quote }}
      key: KURA_CONTROL_PLANE_CLIENT_ID
- name: KURA_CONTROL_PLANE_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ $kuraSharedSecret | quote }}
      key: KURA_CONTROL_PLANE_CLIENT_SECRET
{{- else if ne (.Values.server.externalSecrets.kuraIntrospection.item | default "") "" }}
- name: KURA_CONTROL_PLANE_CLIENT_ID
  valueFrom:
    secretKeyRef:
      name: {{ $esoSecret | quote }}
      key: KURA_CONTROL_PLANE_CLIENT_ID
- name: KURA_CONTROL_PLANE_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ $esoSecret | quote }}
      key: KURA_CONTROL_PLANE_CLIENT_SECRET
{{- end }}
{{- end }}

{{/*
License env vars. Resolves to one mutually exclusive source:
  1. ESO-managed Secret (server.externalSecrets.license.item or
     server.externalSecrets.license.certificateItem set) for managed
     environments that sync the license from 1Password.
  2. Chart-managed app-secrets Secret when server.license.key or
     server.license.certificateBase64 is inlined.
  3. Caller-managed Secret named by server.license.existingSecret, with
     per-field key names from server.license.existingSecretKeys. Use this
     when the license values are populated by an out-of-band flow (Vault,
     sealed-secrets, an ExternalSecret against a non-1Password store, …).
     A blank existingSecretKeys entry skips wiring that env var.
*/}}
{{- define "tuist.licenseEnv" -}}
{{- $appSecret := include "tuist.componentName" (dict "root" . "component" "app-secrets") -}}
{{- $esoSecret := include "tuist.componentName" (dict "root" . "component" "server-external-secrets") -}}
{{- $existingSecret := .Values.server.license.existingSecret | default "" -}}
{{- $existingKeys := .Values.server.license.existingSecretKeys | default dict -}}
{{- $useEsoKey := ne (.Values.server.externalSecrets.license.item | default "") "" -}}
{{- $useEsoCertificate := ne (.Values.server.externalSecrets.license.certificateItem | default "") "" -}}
{{- $useInlineKey := ne (.Values.server.license.key | default "") "" -}}
{{- $useInlineCertificate := ne (.Values.server.license.certificateBase64 | default "") "" -}}
{{- $useExistingKey := and (ne $existingSecret "") (ne (get $existingKeys "key" | default "") "") -}}
{{- $useExistingCertificate := and (ne $existingSecret "") (ne (get $existingKeys "certificateBase64" | default "") "") -}}
{{- if and $useEsoKey $useEsoCertificate -}}
{{- fail "server.externalSecrets.license.item and server.externalSecrets.license.certificateItem are mutually exclusive; pick one license source." -}}
{{- end -}}
{{- if and (or $useEsoKey $useEsoCertificate) (or $useInlineKey $useInlineCertificate) -}}
{{- fail "external and inline license settings are mutually exclusive; pick one license source." -}}
{{- end -}}
{{- if and $useInlineKey $useInlineCertificate -}}
{{- fail "server.license.key and server.license.certificateBase64 are mutually exclusive; pick one license source." -}}
{{- end -}}
{{- if and (ne $existingSecret "") (or $useEsoKey $useEsoCertificate $useInlineKey $useInlineCertificate) -}}
{{- fail "server.license.existingSecret is mutually exclusive with server.license.{key,certificateBase64} and with the server.externalSecrets.license path; pick one license source." -}}
{{- end -}}
{{- if and (ne $existingSecret "") (not (or $useExistingKey $useExistingCertificate)) -}}
{{- fail "server.license.existingSecret is set but neither existingSecretKeys.key nor existingSecretKeys.certificateBase64 names a key; give the chart a license source." -}}
{{- end -}}
{{- if not (or $useEsoKey $useEsoCertificate $useInlineKey $useInlineCertificate $useExistingKey $useExistingCertificate) -}}
{{- fail "no Tuist license source is configured; set exactly one online key or air-gapped certificate source." -}}
{{- end -}}
{{- /*
  Render BOTH the legacy, source-specific env names
  (`TUIST_LICENSE_KEY` / `TUIST_LICENSE_CERTIFICATE_BASE64`) AND the
  unified `TUIST_LICENSE` from the same Secret keys, so the server reads
  the license whichever name a caller or operator keeps using.

  The server's `Tuist.License.fetch_license/0` tries the legacy readers
  first (`license_key`, `license_certificate_base64`) and falls through
  to the unified `license_value` only when both come back nil. That
  makes the legacy variables the authoritative fallback in production:
  if a future bug on the `TUIST_LICENSE` dispatch regresses, the pod
  still boots because the legacy env is also set.

  The previous attempt at a single-env unification (#13750) left the
  pods crashing on canary without a captured log, so we are relanding
  the operator-facing unified name while keeping the belt-and-suspenders
  legacy names until the dispatch path is proven end-to-end.
*/}}
{{- if or $useEsoKey $useInlineKey $useExistingKey }}
- name: TUIST_LICENSE_KEY
  valueFrom:
    secretKeyRef:
      {{- if $useExistingKey }}
      name: {{ $existingSecret | quote }}
      key: {{ get $existingKeys "key" | quote }}
      {{- else }}
      name: {{ ternary $esoSecret $appSecret $useEsoKey | quote }}
      key: server-license-key
      {{- end }}
- name: TUIST_LICENSE
  valueFrom:
    secretKeyRef:
      {{- if $useExistingKey }}
      name: {{ $existingSecret | quote }}
      key: {{ get $existingKeys "key" | quote }}
      {{- else }}
      name: {{ ternary $esoSecret $appSecret $useEsoKey | quote }}
      key: server-license-key
      {{- end }}
{{- end }}
{{- if or $useEsoCertificate $useInlineCertificate $useExistingCertificate }}
- name: TUIST_LICENSE_CERTIFICATE_BASE64
  valueFrom:
    secretKeyRef:
      {{- if $useExistingCertificate }}
      name: {{ $existingSecret | quote }}
      key: {{ get $existingKeys "certificateBase64" | quote }}
      {{- else }}
      name: {{ ternary $esoSecret $appSecret $useEsoCertificate | quote }}
      key: server-license-certificate-base64
      {{- end }}
- name: TUIST_LICENSE
  valueFrom:
    secretKeyRef:
      {{- if $useExistingCertificate }}
      name: {{ $existingSecret | quote }}
      key: {{ get $existingKeys "certificateBase64" | quote }}
      {{- else }}
      name: {{ ternary $esoSecret $appSecret $useEsoCertificate | quote }}
      key: server-license-certificate-base64
      {{- end }}
{{- end }}
{{- end -}}

{{/*
Cache application secret source. Resolves to either the chart-managed
app-secrets Secret (default) or a caller-managed Secret named by
cache.existingSecret, in which case every cache.apiKey / secretKeyBase /
guardianSecretKey inline value must be empty. Fields (env var → key) come
from cache.existingSecretKeys when set, else the app-secrets defaults.
*/}}
{{- define "tuist.cacheSecretName" -}}
{{- $existingSecret := .Values.cache.existingSecret | default "" -}}
{{- if ne $existingSecret "" -}}
{{- if or (ne (.Values.cache.apiKey | default "") "") (ne (.Values.cache.secretKeyBase | default "") "") (ne (.Values.cache.guardianSecretKey | default "") "") -}}
{{- fail "cache.existingSecret is mutually exclusive with cache.{apiKey,secretKeyBase,guardianSecretKey}; clear the inline values or unset cache.existingSecret." -}}
{{- end -}}
{{- $existingSecret -}}
{{- else -}}
{{- include "tuist.componentName" (dict "root" . "component" "app-secrets") -}}
{{- end -}}
{{- end -}}

{{- define "tuist.cacheSecretKey" -}}
{{- $field := .field -}}
{{- $default := .default -}}
{{- $existingSecret := .root.Values.cache.existingSecret | default "" -}}
{{- if ne $existingSecret "" -}}
{{- $keys := .root.Values.cache.existingSecretKeys | default dict -}}
{{- $override := get $keys $field | default "" -}}
{{- if eq $override "" -}}
{{- fail (printf "cache.existingSecretKeys.%s is required when cache.existingSecret is set" $field) -}}
{{- end -}}
{{- $override -}}
{{- else -}}
{{- $default -}}
{{- end -}}
{{- end -}}

{{- define "tuist.serverHeadlessServiceName" -}}
{{- include "tuist.componentName" (dict "root" . "component" "server-headless") -}}
{{- end -}}

{{- define "tuist.githubEnv" -}}
{{- if and .Values.server.enabled .Values.server.github.managedSecrets }}
{{- $secret := include "tuist.componentName" (dict "root" . "component" "github-external-secrets") -}}
- name: TUIST_GITHUB_APP_NAME
  valueFrom:
    secretKeyRef:
      name: {{ $secret | quote }}
      key: app-name
- name: TUIST_GITHUB_APP_ID
  valueFrom:
    secretKeyRef:
      name: {{ $secret | quote }}
      key: app-id
- name: TUIST_GITHUB_APP_CLIENT_ID
  valueFrom:
    secretKeyRef:
      name: {{ $secret | quote }}
      key: app-client-id
- name: TUIST_GITHUB_APP_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ $secret | quote }}
      key: app-client-secret
- name: TUIST_GITHUB_APP_WEBHOOK_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ $secret | quote }}
      key: app-webhook-secret
- name: TUIST_GITHUB_APP_PRIVATE_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $secret | quote }}
      key: app-private-key
- name: TUIST_GITHUB_TOKEN_UPDATE_PACKAGE_RELEASES
  valueFrom:
    secretKeyRef:
      name: {{ $secret | quote }}
      key: token-update-package-releases
- name: TUIST_GITHUB_TOKEN_UPDATE_PACKAGES
  valueFrom:
    secretKeyRef:
      name: {{ $secret | quote }}
      key: token-update-packages
{{- end }}
{{- end -}}

{{- define "tuist.googleEnv" -}}
{{- if and .Values.server.enabled .Values.server.google.managedSecrets }}
{{- $secret := include "tuist.componentName" (dict "root" . "component" "google-external-secrets") -}}
- name: TUIST_GOOGLE_OAUTH_CLIENT_ID
  valueFrom:
    secretKeyRef:
      name: {{ $secret | quote }}
      key: oauth-client-id
- name: TUIST_GOOGLE_OAUTH_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ $secret | quote }}
      key: oauth-client-secret
{{- end }}
{{- end -}}

{{/*
envFrom entry for the consolidated server-config ExternalSecret. Every key in
that Secret is already a TUIST_* env var name, so a single secretRef wires the
whole runtime-secret set into the Server / Migration / Processor containers —
the replacement for decrypting priv/secrets/<env>.yml.enc. Emits nothing when
server.config.managedSecrets is off (self-hosted installs supply config their
own way).
*/}}
{{- define "tuist.serverConfigEnvFrom" -}}
{{- if and .Values.server.enabled .Values.server.config.managedSecrets }}
- secretRef:
    name: {{ include "tuist.componentName" (dict "root" . "component" "server-config-external-secrets") }}
{{- end }}
{{- end -}}

{{/*
Stable credential and desired identifiers for the managed ClickHouse operator
user. The migration job consumes the same values as the web server, so every
release converges the database user before the new pods start.
*/}}
{{- define "tuist.opsClickHouseSecretName" -}}
{{- .Values.server.config.opsClickHouse.existingSecret | default (include "tuist.componentName" (dict "root" . "component" "clickhouse-ops")) -}}
{{- end -}}

{{- define "tuist.opsClickHouseEnv" -}}
{{- if and .Values.server.enabled .Values.server.config.opsClickHouse.enabled }}
- name: TUIST_OPS_CLICKHOUSE_USERNAME
  value: {{ required "server.config.opsClickHouse.username is required when enabled" .Values.server.config.opsClickHouse.username | quote }}
- name: TUIST_OPS_CLICKHOUSE_ROLE
  value: {{ required "server.config.opsClickHouse.role is required when enabled" .Values.server.config.opsClickHouse.role | quote }}
- name: TUIST_OPS_CLICKHOUSE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "tuist.opsClickHouseSecretName" . }}
      key: {{ .Values.server.config.opsClickHouse.passwordKey | default "password" | quote }}
{{- end }}
{{- end -}}

{{/*
The Grafana identity's name and role, for the migration Job that reconciles
it. Its password reaches the Job through the managed external secrets.
*/}}
{{- define "tuist.grafanaClickHouseEnv" -}}
{{- if and .Values.server.enabled .Values.server.config.grafanaClickHouse.enabled }}
{{- if not .Values.server.config.managedSecrets }}
{{- fail "server.config.grafanaClickHouse needs server.config.managedSecrets: its password comes from the managed external secrets." }}
{{- end }}
- name: TUIST_GRAFANA_CLICKHOUSE_USERNAME
  value: {{ required "server.config.grafanaClickHouse.username is required when enabled" .Values.server.config.grafanaClickHouse.username | quote }}
- name: TUIST_GRAFANA_CLICKHOUSE_ROLE
  value: {{ required "server.config.grafanaClickHouse.role is required when enabled" .Values.server.config.grafanaClickHouse.role | quote }}
{{- end }}
{{- end -}}

{{/*
ClickHouse repo pool sizes and the shared user memory budget are non-secret
operational knobs. Render them from chart values so the server, migration,
processor, and xcresult-processor pods stay aligned without relying on the
runtime secret bundle.
*/}}
{{- /*
The in-cluster ClickHouse, for every workload that reads or writes analytics.
*/ -}}
{{- define "tuist.clickhouseManagedEnv" -}}
{{- include "tuist.clickhouseManagedUrlEnvForKey" (dict "root" . "key" "url") }}
{{- end }}

{{/*
The same env, but reading the tailnet URL. Only for writers that are not on the
pod network: the macOS fleet's xcresult-processor runs in a Tart VM with a
tailnet address, so the in-cluster Service name in `url` does not resolve for
it.
*/}}
{{- define "tuist.clickhouseManagedTailnetEnv" -}}
{{- if .Values.clickhouse.managed.tailscale.enabled }}
{{- include "tuist.clickhouseManagedUrlEnvForKey" (dict "root" . "key" "url-tailnet") }}
{{- else }}
{{- include "tuist.clickhouseManagedUrlEnvForKey" (dict "root" . "key" "url") }}
{{- end }}
{{- end }}

{{/*
The name writers off the pod network dial the in-cluster ClickHouse at: the
full MagicDNS name, because the macOS VMs resolve tailnet names through a
resolver scoped to `.ts.net` (infra/xcresult-processor-image/tailscale-up.sh).
The bare name resolves only from a snapshot of peers taken at boot, which
never contains a Tailscale Service and keeps an old address after the name
moves to another device.
*/}}
{{- define "tuist.clickhouseTailnetHost" -}}
{{- include "tuist.tailnetFQDN" (dict "root" . "host" (required "clickhouse.managed.tailscale.hostname is required when tailscale.enabled is true" .Values.clickhouse.managed.tailscale.hostname)) }}
{{- end }}

{{/*
The same for the CNPG pooler the xcresult processor reaches over the tailnet.
*/}}
{{- define "tuist.poolerTailnetHost" -}}
{{- include "tuist.tailnetFQDN" (dict "root" . "host" (required "postgresql.cnpg.pooler.tailscale.hostname is required when tailscale.enabled is true" .Values.postgresql.cnpg.pooler.tailscale.hostname)) }}
{{- end }}

{{- define "tuist.tailnetFQDN" -}}
{{- $host := .host }}
{{- with .root.Values.macosFleet.tailscaleEgress.magicDNSSuffix }}
{{- $host = printf "%s.%s" $host . }}
{{- end }}
{{- $host }}
{{- end }}

{{/*
TUIST_CLICKHOUSE_URL for the in-cluster server as the system of record. Set as
`env`, which takes precedence over a URL an `envFrom` Secret may carry.

Not `optional`: a missing Secret has to keep the pod from starting rather than
let it fall back to another URL.
*/}}
{{- define "tuist.clickhouseManagedUrlEnvForKey" -}}
{{- $key := .key }}
{{- with .root }}
{{- if eq .Values.clickhouse.mode "managed" }}
{{- if not .Values.clickhouse.managed.enabled }}
{{- fail "clickhouse.mode \"managed\" requires clickhouse.managed.enabled, which deploys the server it points at." }}
{{- end }}
- name: TUIST_CLICKHOUSE_URL
  valueFrom:
    secretKeyRef:
      name: {{ include "tuist.componentName" (dict "root" . "component" "clickhouse") }}-credentials
      key: {{ $key }}
{{- end }}
{{- end }}
{{- end }}

{{- define "tuist.clickhousePoolEnv" -}}
{{- with .Values.clickhouse.poolSize }}
- name: TUIST_CLICKHOUSE_POOL_SIZE
  value: {{ . | quote }}
{{- end }}
{{- with .Values.clickhouse.bufferPoolSize }}
- name: TUIST_CLICKHOUSE_BUFFER_POOL_SIZE
  value: {{ . | quote }}
{{- end }}
{{- with .Values.clickhouse.maxMemoryUsageForUserBytes }}
- name: TUIST_CLICKHOUSE_MAX_MEMORY_USAGE_FOR_USER_BYTES
  value: {{ . | quote }}
{{- end }}
{{- end -}}

{{/*
Stripe price IDs. These are not secrets (just identifiers for the products in
Stripe), so they live in chart values as a readable plan -> category -> [ids]
map plus a top-level runner meter event name -> price id map instead of the
secret store. `Tuist.Environment.stripe_prices/1` reads TUIST_STRIPE_PRICES as
a JSON string, so the chart just JSON-encodes the map. Emits nothing when
server.stripe.prices is empty (self-hosted installs without Stripe).
*/}}
{{- define "tuist.stripePricesEnv" -}}
{{- with .Values.server.stripe.prices }}
- name: TUIST_STRIPE_PRICES
  value: {{ toJson . | quote }}
{{- end }}
{{- end -}}

{{/*
Mailing identity env vars. The Mailgun sending domain + from/reply-to addresses
are sender identity, not secrets, so they come from chart values (shared in
values-managed-common.yaml). The Mailgun API key itself stays in the secret
store. Each var is emitted only when set, so an unset value leaves the accessor
nil (mail simply degrades) rather than overriding with "".
*/}}
{{- define "tuist.mailingEnv" -}}
{{- with .Values.server.mailing.domain }}
- name: TUIST_MAILING_DOMAIN
  value: {{ . | quote }}
{{- end }}
{{- with .Values.server.mailing.fromAddress }}
- name: TUIST_MAILING_FROM_ADDRESS
  value: {{ . | quote }}
{{- end }}
{{- with .Values.server.mailing.replyToAddress }}
- name: TUIST_MAILING_REPLY_TO_ADDRESS
  value: {{ . | quote }}
{{- end }}
{{- end -}}

{{- /*
The in-cluster ClickHouse's users configuration: the `default` profile and the
`default` user. A named template because the StatefulSet hashes it into its
`checksum/config` annotation as well as the Secret rendering it, and the
Secret is mounted with `subPath`, which Kubernetes never refreshes, so a
profile change reaches the server only through a restart.
*/}}
{{/*
The managed ClickHouse's `default` cluster: one shard holding every replica,
each through its own Service on the native port. Replicas authenticate to
each other with the interserver secret and run forwarded queries as the user
who sent them, so `clusterAllReplicas('default', ...)` works for any user with
the `REMOTE` grant, without a password per replica.

`replicas` is passed in so the pod checksum can hash the cluster's shape
without its membership (see the checksum in clickhouse-managed.yaml).
*/}}
{{- define "tuist.clickhouseManagedClusterXml" -}}
<clickhouse>
  <remote_servers replace="replace">
    <default>
      <secret from_env="INTERSERVER_HTTP_PASSWORD"></secret>
      <shard>
        <internal_replication>true</internal_replication>
{{- range $i := until (int .replicas) }}
        <replica>
          <host>{{ $.name }}-{{ $i }}.{{ $.namespace }}.svc</host>
          <port>9000</port>
        </replica>
{{- end }}
      </shard>
    </default>
  </remote_servers>
</clickhouse>
{{- end }}

{{- define "tuist.clickhouseManagedUsersXml" -}}
<clickhouse>
  <profiles>
    <default>
      <!--
        Three settings that only matter inside a `Replicated` database,
        and each of which is load-bearing for the Cloud schema clone.

        `allow_only_replicated_engine` is the guard. Without it a CREATE
        that somehow reaches this database with a plain `MergeTree`
        engine succeeds and produces a table whose data lives on one
        replica only, which is invisible until a second replica exists
        and disagrees. With it, that CREATE fails outright. ClickHouse
        Cloud defaults this to 1 for the same reason.

        `allow_replicated_engine_arguments = 2` accepts the explicit
        Keeper path and replica arguments carried by DDL cloned from
        Cloud and substitutes the server defaults instead of honouring
        them. Cloud emits `('/clickhouse/tables/{uuid}/{shard}',
        '{replica}', ...)`, which is the same path this server would
        choose anyway; mode 1 would accept and honour it, and mode 0
        would reject the clone outright.

        `allow_heavy_create` permits `CREATE MATERIALIZED VIEW ...
        POPULATE`, which 14 of the ingest migrations use. It is off by
        default because such a statement holds the distributed DDL queue
        for as long as the backfill runs. That is acceptable here: the
        statements run during migration, not against live traffic.
      -->
      <database_replicated_allow_only_replicated_engine>1</database_replicated_allow_only_replicated_engine>
      <database_replicated_allow_replicated_engine_arguments>2</database_replicated_allow_replicated_engine_arguments>
      <database_replicated_allow_heavy_create>1</database_replicated_allow_heavy_create>

      <!--
        ClickHouse Cloud's settings, which the application's queries are
        written against. Cloud runs with `compatibility = 24.12`, which
        keeps the defaults of every setting that changed after that release,
        so a newer server without it answers some queries differently.

        The rest are what Cloud sets on top of that and the application
        depends on. The HTTP limits apply to how the driver sends a query:
        each parameter is a form field, and this server's defaults of 1,000
        fields and 131,072 bytes per field reject requests Cloud serves, as
        CLI authentication on canary did. Date parsing accepts the formats
        Cloud accepts. Large GROUP BY and ORDER BY spill to disk at 4 GiB,
        because `compatibility` turns off the ratio that would otherwise
        decide it. A read the client abandoned stops running. ALTERs return
        without waiting for their mutations, and tables and partitions up to
        1 TB can be dropped, so migrations behave as they do on Cloud.
      -->
      <compatibility>24.12</compatibility>
      <http_max_fields>1000000</http_max_fields>
      <http_max_field_name_size>131072</http_max_field_name_size>
      <http_max_field_value_size>13107200</http_max_field_value_size>
      <http_max_request_header_size>0</http_max_request_header_size>
      <date_time_input_format>best_effort</date_time_input_format>
      <max_bytes_before_external_group_by>4294967296</max_bytes_before_external_group_by>
      <max_bytes_before_external_sort>4294967296</max_bytes_before_external_sort>
      <cancel_http_readonly_queries_on_client_close>1</cancel_http_readonly_queries_on_client_close>
      <alter_sync>0</alter_sync>
      <replication_alter_partitions_sync>0</replication_alter_partitions_sync>
      <max_table_size_to_drop>1000000000000</max_table_size_to_drop>
      <max_partition_size_to_drop>1000000000000</max_partition_size_to_drop>

      <!--
        Inserts write on several threads and feed materialized views in
        parallel, as Cloud's default profile has them (26.4 reports
        `parallel_view_processing = true` and `max_insert_threads = 4`).
        The open-source defaults are one thread and one view at a time, and
        `test_case_runs` feeds about twenty views: production's backfill
        copied it at 31 to 55 thousand rows a second on one core of 30,
        against 300 to 800 thousand for tables without views. The same
        default governs the application's own buffer flushes once this
        server is the system of record.
      -->
      <parallel_view_processing>1</parallel_view_processing>
      <max_insert_threads>4</max_insert_threads>
    </default>

    <!--
      The backup CronJobs' own user, so a backup is bounded by its own
      budget rather than the application's. ClickHouse enforces
      `max_memory_usage_for_user` on one tracker per user, and the
      application sets that tracker's ceiling on every query it sends. A
      backup running as `default` therefore shares the application's
      budget, which production's nightly incremental outgrew at 10 GiB
      against 8.
    -->
    <backup>
      <profile>default</profile>
{{- with .backup.maxMemoryUsageForUserBytes }}
      <max_memory_usage_for_user>{{ . }}</max_memory_usage_for_user>
{{- end }}
    </backup>
  </profiles>
  <users>
    <default>
      <password>{{ .password }}</password>
      <networks>
        <ip>::/0</ip>
      </networks>
      <profile>default</profile>
      <quota>default</quota>
      <access_management>1</access_management>
    </default>
    <backup>
      <password>{{ .password }}</password>
      <networks>
        <ip>::/0</ip>
      </networks>
      <profile>backup</profile>
      <quota>default</quota>
    </backup>
  </users>
</clickhouse>
{{- end }}

{{/* Both platforms use one server-authenticated cache agent identity. */}}
{{- define "tuist.runnerCacheVolumesNamespace" -}}
{{- $mac := .Values.runnersFleet.namespace | default "tuist-runners" -}}
{{- $linux := .Values.runnersFleetLinux.namespace | default $mac -}}
{{- if .Values.runnersFleet.customCacheVolumes.enabled -}}
{{- if and .Values.runnersFleetLinux.enabled .Values.runnersFleetLinux.cacheVolumes.enabled (ne $mac $linux) -}}
{{- fail "macOS and Linux custom cache volumes must use the same runners namespace" -}}
{{- end -}}
{{- $mac -}}
{{- else -}}
{{- $linux -}}
{{- end -}}
{{- end -}}

{{/*
Resolve the effective Once events ingress config.

Returns a YAML dict callers decode with `fromYaml`:
    enabled, host, tlsSecretName, annotations, className, source

Precedence:
  - If BOTH `server.events.enabled` and `server.bazelEvents.enabled` are
    true, fail: operators mid-migration must pick one key before
    continuing so we don't silently keep the deprecated block alive.
  - If `server.events.enabled` is true -> use `server.events` (source =
    "server.events").
  - Else if `server.bazelEvents.enabled` is true -> use
    `server.bazelEvents` as the one-release deprecation path for
    #13184 adopters (source = "server.bazelEvents").
  - Else disabled.

The returned `source` is used by callers to name the right key in
`required`/`fail` error messages, so deprecated-key operators are not
told to fix a key they are not using.
*/}}
{{- define "tuist.serverEventsConfig" -}}
{{- $events := .Values.server.events | default dict -}}
{{- $bazel := .Values.server.bazelEvents | default dict -}}
{{- if and $events.enabled $bazel.enabled -}}
{{- fail "server.events.enabled and server.bazelEvents.enabled are mutually exclusive; the `bazelEvents` key is a one-release alias for `events` (#13184 migration), remove it from your values before enabling `events`." -}}
{{- end -}}
{{- $effective := dict "enabled" false "host" "" "tlsSecretName" "" "annotations" dict "className" "" "source" "server.events" -}}
{{- if $events.enabled -}}
{{- $effective = dict "enabled" true "host" ($events.host | default "") "tlsSecretName" ($events.tlsSecretName | default "") "annotations" ($events.annotations | default dict) "className" ($events.className | default "") "source" "server.events" -}}
{{- else if $bazel.enabled -}}
{{- $effective = dict "enabled" true "host" ($bazel.host | default "") "tlsSecretName" ($bazel.tlsSecretName | default "") "annotations" ($bazel.annotations | default dict) "className" ($bazel.className | default "") "source" "server.bazelEvents" -}}
{{- end -}}
{{- toYaml $effective -}}
{{- end -}}

{{/*
URL scheme the discovery doc should advertise for the Once events gRPC
endpoint: `grpcs` when TLS terminates at the ingress (any
`tlsSecretName` set), otherwise `grpc`. Keeps non-TLS self-hosted
installs from advertising a scheme their ingress cannot serve.

Takes the context root. Reads the same effective events config as the
Deployment and Ingress templates.
*/}}
{{- define "tuist.serverEventsScheme" -}}
{{- $events := include "tuist.serverEventsConfig" . | fromYaml -}}
{{- if $events.tlsSecretName -}}
grpcs
{{- else -}}
grpc
{{- end -}}
{{- end -}}

{{/*
The runner image for a catalog Xcode version: the `imageTag` its
`runnersFleet.xcodeOverrides` entry pins, else
`<runnersFleet.runnerImageRepository>@<digest>` with the digest
`runnersFleet.runnerImageDigests` resolves for it, else
`<runnersFleet.runnerImageRepository>:macos-<xcode-dashes>-<runnerImageSemver>`.
Deploys resolve the digests, so a release that re-tags an unchanged profile
leaves its pools' image as it was: the controller does not roll their Pods
and hosts keep the golden the ref names. The image is a property of the Xcode,
not of the fleet it runs on, so every pool that runs an Xcode (the rented
fleet's, a rack's, an explicit pool naming `xcodeVersion`) takes it from here
and follows a release together.
*/}}
{{- define "tuist.macosRunnerImage" -}}
{{- $root := .root -}}
{{- $xcodeVersion := .xcodeVersion | toString -}}
{{- $repo := $root.Values.runnersFleet.runnerImageRepository | default "" -}}
{{- $semver := $root.Values.runnersFleet.runnerImageSemver | default "" -}}
{{- $override := dig $xcodeVersion (dict) ($root.Values.runnersFleet.xcodeOverrides | default dict) -}}
{{- $digest := get ($root.Values.runnersFleet.runnerImageDigests | default dict) $xcodeVersion | default "" | toString -}}
{{- if not $repo -}}
  {{- fail "runnersFleet.runnerImageRepository required when runnersFleet.xcodeVersions is non-empty" -}}
{{- end -}}
{{- if dig "imageTag" "" $override -}}
  {{- printf "%s:%s" $repo $override.imageTag -}}
{{- else if $digest -}}
  {{- if not (regexMatch "^sha256:[a-f0-9]{64}$" $digest) -}}
    {{- fail (printf "runnersFleet.runnerImageDigests[%s] is %q, not a sha256:<64 hex> manifest digest" $xcodeVersion $digest) -}}
  {{- end -}}
  {{- printf "%s@%s" $repo $digest -}}
{{- else if $semver -}}
  {{- printf "%s:macos-%s-%s" $repo ($xcodeVersion | replace "." "-") $semver -}}
{{- else -}}
  {{- fail (printf "runnersFleet.runnerImageSemver required when runnersFleet.xcodeVersions is non-empty and Xcode %s has no runnerImageDigests entry or imageTag override" $xcodeVersion) -}}
{{- end -}}
{{- end -}}

{{/*
The stacked runner image for a catalog Xcode version:
`<runnersFleet.runnerImageRepository>@<digest>` with the digest
`runnersFleet.runnerImageStackedDigests` resolves for it, or empty when it has
none or its `runnersFleet.xcodeOverrides` entry pins an `imageTag`, in which
case the pool runs `tuist.macosRunnerImage`.
*/}}
{{- define "tuist.macosRunnerStackedImage" -}}
{{- $root := .root -}}
{{- $xcodeVersion := .xcodeVersion | toString -}}
{{- $override := dig $xcodeVersion (dict) ($root.Values.runnersFleet.xcodeOverrides | default dict) -}}
{{- $digest := get ($root.Values.runnersFleet.runnerImageStackedDigests | default dict) $xcodeVersion | default "" | toString -}}
{{- if and $digest (not (dig "imageTag" "" $override)) -}}
  {{- if not (regexMatch "^sha256:[a-f0-9]{64}$" $digest) -}}
    {{- fail (printf "runnersFleet.runnerImageStackedDigests[%s] is %q, not a sha256:<64 hex> manifest digest" $xcodeVersion $digest) -}}
  {{- end -}}
  {{- printf "%s@%s" $root.Values.runnersFleet.runnerImageRepository $digest -}}
{{- end -}}
{{- end -}}

{{/*
The macOS catalog pools racked at the rack fleet's site, as a list of
`{name, site}` in JSON: every `runnersFleet.xcodeVersions` entry on the
catalog's default shape, plus each non-default shape `rackFleet.runners.shapes`
names. `templates/runner-pool.yaml` renders exactly these, and the server
learns them through TUIST_RUNNERS_SITE_POOLS, which is how it knows which
profiles a site can serve. Empty unless `rackFleet.runners.enabled`, which
does not need `rackFleet.enabled`: an env whose rack hosts are lent to it by
another env (`rackFleet.borrow`) runs the pools without owning the hosts.
*/}}
{{- define "tuist.rackCatalogPools" -}}
{{- $pools := list -}}
{{- if and .Values.runnersFleet.enabled (dig "runners" "enabled" false .Values.rackFleet) -}}
{{- $site := required "rackFleet.site is required when rackFleet.runners.enabled is true" .Values.rackFleet.site -}}
{{- $prefix := include "tuist.componentName" (dict "root" . "component" "runner-pool-macos") -}}
{{- $rackShapes := dig "runners" "shapes" (dict) .Values.rackFleet -}}
{{- range $xcode := (.Values.runnersFleet.xcodeVersions | default list) -}}
{{- $xcodeTag := required "runnersFleet.xcodeVersions[].xcodeVersion required" $xcode.xcodeVersion | toString | replace "." "-" -}}
{{- $pools = append $pools (dict "name" (printf "%s-%s-%s" $prefix $site $xcodeTag) "site" $site) -}}
{{- range $shape := ($.Values.runnersFleet.shapes | default list) -}}
{{- if not $shape.default -}}
{{- $shapeKey := printf "%dvcpu-%dgb" (int $shape.vcpus) (int $shape.memoryGb) -}}
{{- if hasKey $rackShapes $shapeKey -}}
{{- $pools = append $pools (dict "name" (printf "%s-%s-%s-%s" $prefix $site $xcodeTag $shapeKey) "site" $site) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $pools | toJson -}}
{{- end -}}

{{/*
The Secret holding the credential this env's operator reaches a borrowing
env's RackHostLeases with: `rackFleet.borrowers.<env>`.
*/}}
{{- define "tuist.rackBorrowerSecret" -}}
{{- printf "%s-%s" (include "tuist.componentName" (dict "root" .root "component" "rack-borrower")) .env | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
The identity a lending env's operator writes this env's RackHostLeases with.
*/}}
{{- define "tuist.rackLenderName" -}}
{{- include "tuist.componentName" (dict "root" . "component" "rack-lender") -}}
{{- end -}}

{{/*
"true" unless the env racks its macOS catalog at a site
(`tuist.rackCatalogPools`) and rents no Scaleway hosts for it
(`runnersFleet.hostCount` and every `machineGroups[].hostCount` at 0). Without
rented hosts the chart renders no rented macOS catalog pools, and the server
(TUIST_RUNNERS_RENTED_MACOS_FLEET) keeps every site job at the site instead of
falling back or spilling over to a fleet that is not there.
*/}}
{{- define "tuist.runnersFleetRentsMacOS" -}}
{{- $hosts := int (.Values.runnersFleet.hostCount | default 0) -}}
{{- range (.Values.runnersFleet.machineGroups | default list) -}}
{{- $hosts = add $hosts (int (.hostCount | default 0)) -}}
{{- end -}}
{{- if and (eq (int $hosts) 0) (include "tuist.rackCatalogPools" . | fromJsonArray) -}}
false
{{- else -}}
true
{{- end -}}
{{- end -}}

{{/*
The Secret a lent rack host's kubeconfig is synced into: the 1Password item's
name as a Kubernetes name, so a rotated kubeconfig (a new item) is a new
Secret, and the new name drifts the host onto it.
*/}}
{{- define "tuist.rackNodeKubeconfigSecret" -}}
{{- $item := required (printf "rackFleet.hosts[%s].nodeCluster.kubeconfigItem is required: the 1Password item holding the kubeconfig the other cluster issued" .host) .item -}}
{{- if not (regexMatch "^[A-Za-z0-9_]+$" $item) -}}
{{- fail (printf "rackFleet.hosts[%s].nodeCluster.kubeconfigItem %q must be letters, digits and underscores" .host $item) -}}
{{- end -}}
{{- $item | lower | replace "_" "-" | trunc 63 -}}
{{- end -}}

{{/*
The rack's VM image caches as tart-kubelet's `--image-mirror` entries,
comma-separated in the order of `rackFleet.imageCache.nodes`: empty unless
the caches run and the hosts are routed through them. The rack-nodes chart
runs each cache at the same address and port.
*/}}
{{- define "tuist.rackImageMirrors" -}}
{{- $cache := .Values.rackFleet.imageCache | default dict -}}
{{- $mirrors := list -}}
{{- if and $cache.enabled $cache.routeHosts -}}
{{- $upstream := required "rackFleet.imageCache.upstream is required" $cache.upstream -}}
{{- range $node := (required "rackFleet.imageCache.nodes needs a node to route the hosts to" $cache.nodes) -}}
{{- $address := required (printf "rackFleet.imageCache.nodes[%s].address is required" $node.name) $node.address -}}
{{- $mirrors = append $mirrors (printf "%s=http://%s:%d" $upstream $address (int $cache.port)) -}}
{{- end -}}
{{- end -}}
{{- join "," $mirrors -}}
{{- end -}}

{{/*
The rack hosts routed through the image caches, comma-separated, for
`--rackhost-image-mirror-hosts`. Each is a `rackFleet.hosts[].name`, or `*`
for every host; a name the inventory does not have fails the render rather
than routing nothing.
*/}}
{{- define "tuist.rackImageMirrorHosts" -}}
{{- $routed := .Values.rackFleet.imageCache.routeHosts | default list -}}
{{- if not (kindIs "slice" $routed) -}}
{{- fail "rackFleet.imageCache.routeHosts is a list of rackFleet.hosts[].name, or [\"*\"] for every host" -}}
{{- end -}}
{{- $known := list -}}
{{- range (.Values.rackFleet.hosts | default list) -}}
{{- $known = append $known .name -}}
{{- end -}}
{{- range $routed -}}
{{- if and (ne . "*") (not (has . $known)) -}}
{{- fail (printf "rackFleet.imageCache.routeHosts names %s, which is not in rackFleet.hosts" .) -}}
{{- end -}}
{{- end -}}
{{- join "," $routed -}}
{{- end -}}
