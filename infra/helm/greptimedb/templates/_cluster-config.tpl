{{/* Rendered once for the ConfigMap and once for the pod's restart checksum. */}}
{{- define "greptimedb.metasrvConfig" -}}
{{- $etcd := include "greptimedb.peers" (list "greptimedb-etcd" 2379) }}
{{- $kafka := include "greptimedb.peers" (list "greptimedb-kafka" 9092) }}
{{- $metasrv := printf "[\"%s:3002\"]" (include "greptimedb.svc" "greptimedb-metasrv") -}}
data_home = "/tmp/greptimedb"
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
topic_name_prefix = "greptimedb_wal_topic"
replication_factor = 3
create_topic_timeout = "30s"
{{ include "greptimedb.logging" . }}
{{- end }}

{{- define "greptimedb.datanodeConfig" -}}
{{- $etcd := include "greptimedb.peers" (list "greptimedb-etcd" 2379) }}
{{- $kafka := include "greptimedb.peers" (list "greptimedb-kafka" 9092) }}
{{- $metasrv := printf "[\"%s:3002\"]" (include "greptimedb.svc" "greptimedb-metasrv") -}}
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
data_home = "/data/greptimedb"
type = "S3"
bucket = {{ .Values.storage.bucket | quote }}
endpoint = {{ .Values.storage.endpoint | quote }}
region = {{ .Values.storage.region | quote }}
root = {{ printf "%sdistributed/" .Values.storage.prefix | quote }}
[[region_engine]]
[region_engine.mito]
num_workers = 2
auto_flush_interval = "1m"
global_write_buffer_size = "128MB"
global_write_buffer_reject_size = "256MB"
write_cache_size = {{ .Values.cluster.datanode.writeCacheSize | quote }}
{{ include "greptimedb.logging" . }}
{{- end }}

{{- define "greptimedb.frontendConfig" -}}
{{- $etcd := include "greptimedb.peers" (list "greptimedb-etcd" 2379) }}
{{- $kafka := include "greptimedb.peers" (list "greptimedb-kafka" 9092) }}
{{- $metasrv := printf "[\"%s:3002\"]" (include "greptimedb.svc" "greptimedb-metasrv") -}}
enable_telemetry = false
user_provider = "static_user_provider:file:/etc/greptimedb/auth/passwd"
max_in_flight_write_bytes = "64MB"
[http]
addr = "0.0.0.0:4000"
timeout = "30s"
[grpc]
bind_addr = "0.0.0.0:4001"
[mysql]
enable = false
[postgres]
enable = false
[meta_client]
metasrv_addrs = {{ $metasrv }}
{{ include "greptimedb.logging" . }}
{{- end }}

{{- define "greptimedb.kafkaServerProperties" -}}
{{- $etcd := include "greptimedb.peers" (list "greptimedb-etcd" 2379) }}
{{- $kafka := include "greptimedb.peers" (list "greptimedb-kafka" 9092) }}
{{- $metasrv := printf "[\"%s:3002\"]" (include "greptimedb.svc" "greptimedb-metasrv") -}}
process.roles=broker,controller
controller.quorum.voters=0@greptimedb-kafka-0.greptimedb-kafka.observability.svc.cluster.local:9093,1@greptimedb-kafka-1.greptimedb-kafka.observability.svc.cluster.local:9093,2@greptimedb-kafka-2.greptimedb-kafka.observability.svc.cluster.local:9093
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
# Greptime deletes WAL records once their regions are flushed to object
# storage. Time-based deletion could drop acknowledged, unflushed writes.
log.retention.ms=-1
{{- end }}

{{- define "greptimedb.kafkaLog4j" -}}
{{- $etcd := include "greptimedb.peers" (list "greptimedb-etcd" 2379) }}
{{- $kafka := include "greptimedb.peers" (list "greptimedb-kafka" 9092) }}
{{- $metasrv := printf "[\"%s:3002\"]" (include "greptimedb.svc" "greptimedb-metasrv") -}}
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
