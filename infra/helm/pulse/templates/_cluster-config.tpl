{{/* Rendered once for the ConfigMap and once for the pod's restart checksum. */}}
{{- define "pulse.metasrvConfig" -}}
{{- $etcd := include "pulse.peers" (list "pulse-etcd" 2379) }}
{{- $kafka := include "pulse.peers" (list "pulse-kafka" 9092) }}
{{- $metasrv := printf "[\"%s:3002\"]" (include "pulse.svc" "pulse-metasrv") -}}
data_home = "/tmp/pulse"
enable_telemetry = false
backend = "etcd_store"
store_addrs = {{ $etcd }}
selector = "round_robin"
# Regions on a failed datanode reopen elsewhere from the shared Kafka WAL.
# Never enable allow_region_failover_on_local_wal: it can lose data.
enable_region_failover = true
allow_region_failover_on_local_wal = false
[grpc]
bind_addr = "0.0.0.0:3002"
[http]
addr = "0.0.0.0:4000"
[wal]
provider = "kafka"
broker_endpoints = {{ $kafka }}
auto_create_topics = true
num_topics = 16
topic_name_prefix = "{{ include "pulse.walTopicPrefix" . }}"
replication_factor = 3
create_topic_timeout = "30s"
{{- if has .Values.environment .Values.cluster.gc.environments }}
[gc]
enable = true
{{- end }}
{{ include "pulse.logging" . }}
{{- end }}

{{- define "pulse.datanodeConfig" -}}
{{- $etcd := include "pulse.peers" (list "pulse-etcd" 2379) }}
{{- $kafka := include "pulse.peers" (list "pulse-kafka" 9092) }}
{{- $metasrv := printf "[\"%s:3002\"]" (include "pulse.svc" "pulse-metasrv") -}}
enable_telemetry = false
require_lease_before_startup = true
init_regions_in_background = false
[grpc]
bind_addr = "0.0.0.0:3001"
[http]
addr = "0.0.0.0:4000"
timeout = "30s"
[meta_client]
metasrv_addrs = {{ $metasrv }}
[wal]
provider = "kafka"
broker_endpoints = {{ $kafka }}
max_batch_bytes = "1MB"
# Missing WAL entries are an error, never silently skipped.
overwrite_entry_start_id = false
[storage]
data_home = "/data/pulse"
type = "S3"
bucket = {{ .Values.storage.bucket | quote }}
endpoint = {{ .Values.storage.endpoint | quote }}
region = {{ .Values.storage.region | quote }}
root = {{ printf "%sdistributed/" .Values.storage.prefix | quote }}
[[region_engine]]
[region_engine.mito]
num_workers = 2
auto_flush_interval = "1m"
global_write_buffer_size = {{ .Values.cluster.datanode.writeBufferSize | quote }}
global_write_buffer_reject_size = {{ .Values.cluster.datanode.writeBufferRejectSize | quote }}
write_cache_size = {{ .Values.cluster.datanode.writeCacheSize | quote }}
{{- if has .Values.environment .Values.cluster.gc.environments }}
[region_engine.mito.gc]
enable = true
{{- end }}
{{ include "pulse.logging" . }}
{{- end }}

{{- define "pulse.frontendConfig" -}}
{{- $etcd := include "pulse.peers" (list "pulse-etcd" 2379) }}
{{- $kafka := include "pulse.peers" (list "pulse-kafka" 9092) }}
{{- $metasrv := printf "[\"%s:3002\"]" (include "pulse.svc" "pulse-metasrv") -}}
enable_telemetry = false
user_provider = "static_user_provider:file:/etc/pulse/auth/passwd"
max_in_flight_write_bytes = "64MB"
[http]
addr = "0.0.0.0:4000"
timeout = "30s"
[grpc]
bind_addr = "0.0.0.0:4001"
# The flownode queries frontends here, without the static users. Only Pulse's
# own pods reach this port (pulse-internal); clients reach 4000 and 4003.
[internal_grpc]
bind_addr = "0.0.0.0:4010"
[mysql]
enable = false
[postgres]
{{- if include "pulse.postgres" . }}
enable = true
addr = "0.0.0.0:4003"
{{- else }}
enable = false
{{- end }}
[meta_client]
metasrv_addrs = {{ $metasrv }}
{{ include "pulse.logging" . }}
{{- end }}

{{- define "pulse.flownodeConfig" -}}
{{- $metasrv := printf "[\"%s:3002\"]" (include "pulse.svc" "pulse-metasrv") -}}
# One flownode, so its ID never changes; the Deployment never runs two.
node_id = 0
enable_telemetry = false
[grpc]
bind_addr = "0.0.0.0:3004"
[http]
addr = "0.0.0.0:4000"
[meta_client]
metasrv_addrs = {{ $metasrv }}
{{ include "pulse.logging" . }}
{{- end }}

{{- define "pulse.kafkaServerProperties" -}}
{{- $etcd := include "pulse.peers" (list "pulse-etcd" 2379) }}
{{- $kafka := include "pulse.peers" (list "pulse-kafka" 9092) }}
{{- $metasrv := printf "[\"%s:3002\"]" (include "pulse.svc" "pulse-metasrv") -}}
process.roles=broker,controller
controller.quorum.voters=0@pulse-kafka-0.pulse-kafka.observability.svc.cluster.local:9093,1@pulse-kafka-1.pulse-kafka.observability.svc.cluster.local:9093,2@pulse-kafka-2.pulse-kafka.observability.svc.cluster.local:9093
listeners=PLAINTEXT://:9092,CONTROLLER://:9093
controller.listener.names=CONTROLLER
inter.broker.listener.name=PLAINTEXT
listener.security.protocol.map=PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT
log.dirs=/var/lib/kafka/data/kraft
num.partitions=1
default.replication.factor=3
min.insync.replicas=2
unclean.leader.election.enable=false
auto.create.topics.enable=false
offsets.topic.replication.factor=3
transaction.state.log.replication.factor=3
transaction.state.log.min.isr=2
# Pulse deletes WAL records once their regions are flushed to object
# storage. Time-based deletion could drop acknowledged, unflushed writes.
log.retention.ms=-1
# Kafka frees disk only by deleting whole closed segments. A topic with the
# default 1 GiB segment keeps all its pruned records until the segment fills,
# and 16 topics of that outgrow the volume, so roll at 128 MiB instead.
log.segment.bytes=134217728
{{- end }}

{{- define "pulse.kafkaLog4j" -}}
{{- $etcd := include "pulse.peers" (list "pulse-etcd" 2379) }}
{{- $kafka := include "pulse.peers" (list "pulse-kafka" 9092) }}
{{- $metasrv := printf "[\"%s:3002\"]" (include "pulse.svc" "pulse-metasrv") -}}
Configuration:
  Appenders:
    Console:
      name: STDOUT
      PatternLayout:
        pattern: "[%d] %p %m (%c)%n"
  Loggers:
    Root:
      level: INFO
      AppenderRef:
        - ref: STDOUT
{{- end }}
