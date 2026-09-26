defmodule Once.Events.V1.AckDisposition do
  @moduledoc false
  use Protobuf, enum: true, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :ACK_DISPOSITION_UNSPECIFIED, 0
  field :ACK_DISPOSITION_ACCEPTED, 1
  field :ACK_DISPOSITION_REJECTED_STALE, 2
  field :ACK_DISPOSITION_REJECTED_INVALID, 3
  field :ACK_DISPOSITION_NEEDS_RESYNC, 4
end

defmodule Once.Events.V1.RunFinalization do
  @moduledoc false
  use Protobuf, enum: true, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :RUN_FINALIZATION_UNSPECIFIED, 0
  field :RUN_FINALIZATION_ACTIVE, 1
  field :RUN_FINALIZATION_FINALIZING, 2
  field :RUN_FINALIZATION_FINALIZED, 3
  field :RUN_FINALIZATION_FINALIZATION_PENDING, 4
  field :RUN_FINALIZATION_LOST, 5
end

defmodule Once.Events.V1.HashAlgorithm do
  @moduledoc false
  use Protobuf, enum: true, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :HASH_ALGORITHM_UNSPECIFIED, 0
  field :HASH_ALGORITHM_BLAKE3, 1
  field :HASH_ALGORITHM_SHA256, 2
end

defmodule Once.Events.V1.RunResult do
  @moduledoc false
  use Protobuf, enum: true, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :RUN_RESULT_UNSPECIFIED, 0
  field :RUN_RESULT_SUCCEEDED, 1
  field :RUN_RESULT_FAILED, 2
  field :RUN_RESULT_CANCELLED, 3
  field :RUN_RESULT_TIMED_OUT, 4
  field :RUN_RESULT_INFRASTRUCTURE_ERROR, 5
end

defmodule Once.Events.V1.Phase do
  @moduledoc false
  use Protobuf, enum: true, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :PHASE_UNSPECIFIED, 0
  field :PHASE_QUEUED, 1
  field :PHASE_CACHE_CHECKING, 2
  field :PHASE_PREPARING, 3
  field :PHASE_EXECUTING, 4
  field :PHASE_CAPTURING, 5
  field :PHASE_PUBLISHING, 6
end

defmodule Once.Events.V1.WaitReason do
  @moduledoc false
  use Protobuf, enum: true, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :WAIT_REASON_UNSPECIFIED, 0
  field :WAIT_REASON_DEPENDENCY_WAIT, 1
  field :WAIT_REASON_RESOURCE_WAIT, 2
  field :WAIT_REASON_WORKER_WAIT, 3
  field :WAIT_REASON_THROTTLED, 4
  field :WAIT_REASON_INFRASTRUCTURE, 5
end

defmodule Once.Events.V1.TargetResult do
  @moduledoc false
  use Protobuf, enum: true, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :TARGET_RESULT_UNSPECIFIED, 0
  field :TARGET_RESULT_SUCCEEDED, 1
  field :TARGET_RESULT_FAILED, 2
  field :TARGET_RESULT_SKIPPED, 3
  field :TARGET_RESULT_CANCELLED, 4
  field :TARGET_RESULT_TIMED_OUT, 5
  field :TARGET_RESULT_INFRASTRUCTURE_ERROR, 6
end

defmodule Once.Events.V1.TestCaseResult do
  @moduledoc false
  use Protobuf, enum: true, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :TEST_CASE_RESULT_UNSPECIFIED, 0
  field :TEST_CASE_RESULT_PASSED, 1
  field :TEST_CASE_RESULT_FAILED, 2
  field :TEST_CASE_RESULT_SKIPPED, 3
  field :TEST_CASE_RESULT_TIMED_OUT, 4
  field :TEST_CASE_RESULT_ERRORED, 5
  field :TEST_CASE_RESULT_CANCELLED, 6
  field :TEST_CASE_RESULT_UNKNOWN, 7
end

defmodule Once.Events.V1.Stream do
  @moduledoc false
  use Protobuf, enum: true, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :STREAM_UNSPECIFIED, 0
  field :STREAM_STDOUT, 1
  field :STREAM_STDERR, 2
end

defmodule Once.Events.V1.CacheOutcome do
  @moduledoc false
  use Protobuf, enum: true, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :CACHE_OUTCOME_UNSPECIFIED, 0
  field :CACHE_OUTCOME_HIT, 1
  field :CACHE_OUTCOME_MISS, 2
  field :CACHE_OUTCOME_ERROR, 3
  field :CACHE_OUTCOME_BYPASSED, 4
end

defmodule Once.Events.V1.MissReasonKind do
  @moduledoc false
  use Protobuf, enum: true, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :MISS_REASON_KIND_UNSPECIFIED, 0
  field :MISS_REASON_KIND_FIRST_SEEN, 1
  field :MISS_REASON_KIND_INPUTS_CHANGED, 2
  field :MISS_REASON_KIND_COMMAND_CHANGED, 3
  field :MISS_REASON_KIND_ENV_CHANGED, 4
  field :MISS_REASON_KIND_TOOL_CHANGED, 5
  field :MISS_REASON_KIND_SALT_CHANGED, 6
  field :MISS_REASON_KIND_UNKNOWN, 7
end

defmodule Once.Events.V1.MissAnalysisStatus do
  @moduledoc false
  use Protobuf, enum: true, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :MISS_ANALYSIS_STATUS_UNSPECIFIED, 0
  field :MISS_ANALYSIS_STATUS_COMPLETE, 1
  field :MISS_ANALYSIS_STATUS_PARTIAL, 2
  field :MISS_ANALYSIS_STATUS_TRUNCATED, 3
  field :MISS_ANALYSIS_STATUS_UNAVAILABLE, 4
end

defmodule Once.Events.V1.Severity do
  @moduledoc false
  use Protobuf, enum: true, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :SEVERITY_UNSPECIFIED, 0
  field :SEVERITY_NOTE, 1
  field :SEVERITY_WARNING, 2
  field :SEVERITY_ERROR, 3
end

defmodule Once.Events.V1.ResourceScope do
  @moduledoc false
  use Protobuf, enum: true, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :RESOURCE_SCOPE_UNSPECIFIED, 0
  field :RESOURCE_SCOPE_HOST, 1
  field :RESOURCE_SCOPE_CONTAINER, 2
  field :RESOURCE_SCOPE_PROCESS, 3
  field :RESOURCE_SCOPE_WORKER, 4
end

defmodule Once.Events.V1.GetServerCapabilitiesRequest do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3
end

defmodule Once.Events.V1.GetRunAckRequest do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :run_id, 1, type: :string, json_name: "runId"
end

defmodule Once.Events.V1.GetArgvHashKeyRequest do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :project_id, 1, type: :string, json_name: "projectId"
end

defmodule Once.Events.V1.ServerCapabilities do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :supported_protocol_versions, 1,
    repeated: true,
    type: :string,
    json_name: "supportedProtocolVersions"

  field :max_batch_bytes, 2, type: :uint32, json_name: "maxBatchBytes"
  field :max_event_bytes, 3, type: :uint32, json_name: "maxEventBytes"
  field :max_unacked_events, 4, type: :uint32, json_name: "maxUnackedEvents"
  field :max_log_chunk_bytes, 5, type: :uint32, json_name: "maxLogChunkBytes"
  field :required_features, 6, repeated: true, type: :string, json_name: "requiredFeatures"
  field :log_ingestion_available, 7, type: :bool, json_name: "logIngestionAvailable"
  field :raw_event_retention_available, 8, type: :bool, json_name: "rawEventRetentionAvailable"
  field :finalization_grace_ms, 9, type: :uint32, json_name: "finalizationGraceMs"
  field :dedup_retention_seconds, 10, type: :uint32, json_name: "dedupRetentionSeconds"

  field :safe_literal_allowlist_version, 11,
    type: :string,
    json_name: "safeLiteralAllowlistVersion"
end

defmodule Once.Events.V1.ArgvHashKey do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :key_id, 1, type: :string, json_name: "keyId"
  field :key_bytes, 2, type: :bytes, json_name: "keyBytes"
  field :expires_at_epoch_ms, 3, type: :int64, json_name: "expiresAtEpochMs"
  field :grace_after_expiry_ms, 4, type: :uint32, json_name: "graceAfterExpiryMs"
end

defmodule Once.Events.V1.RunEventBatch do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :run_id, 1, type: :string, json_name: "runId"
  field :batch_id, 2, type: :string, json_name: "batchId"

  field :gap_advances, 3,
    repeated: true,
    type: Once.Events.V1.GapAdvance,
    json_name: "gapAdvances"

  field :seq_from, 4, type: :uint64, json_name: "seqFrom"
  field :events, 5, repeated: true, type: Once.Events.V1.RunEvent
  field :producer_dropped_events, 6, type: :uint64, json_name: "producerDroppedEvents"
end

defmodule Once.Events.V1.GapAdvance do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :first_dropped_seq, 1, type: :uint64, json_name: "firstDroppedSeq"
  field :last_dropped_seq, 2, type: :uint64, json_name: "lastDroppedSeq"
  field :reason, 3, type: :string
end

defmodule Once.Events.V1.BatchAck do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :run_id, 1, type: :string, json_name: "runId"
  field :batch_id, 2, type: :string, json_name: "batchId"
  field :disposition, 3, type: Once.Events.V1.AckDisposition, enum: true
  field :acked_seq, 4, type: :uint64, json_name: "ackedSeq"
  field :expected_next_seq, 5, type: :uint64, json_name: "expectedNextSeq"
  field :observed_high_water_seq, 6, type: :uint64, json_name: "observedHighWaterSeq"
  field :retry_after_ms, 7, type: :uint32, json_name: "retryAfterMs"
  field :max_in_flight_batches, 8, type: :uint32, json_name: "maxInFlightBatches"
  field :finalization, 9, type: Once.Events.V1.RunFinalization, enum: true
  field :dashboard_url, 10, type: :string, json_name: "dashboardUrl"
end

defmodule Once.Events.V1.RunEventAck do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :run_id, 1, type: :string, json_name: "runId"
  field :acked_seq, 2, type: :uint64, json_name: "ackedSeq"
  field :expected_next_seq, 3, type: :uint64, json_name: "expectedNextSeq"
  field :observed_high_water_seq, 4, type: :uint64, json_name: "observedHighWaterSeq"
  field :finalization, 5, type: Once.Events.V1.RunFinalization, enum: true
  field :dashboard_url, 6, type: :string, json_name: "dashboardUrl"
end

defmodule Once.Events.V1.ContentRef do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :hash_algorithm, 1,
    type: Once.Events.V1.HashAlgorithm,
    json_name: "hashAlgorithm",
    enum: true

  field :digest, 2, type: :bytes
  field :size_bytes, 3, type: :uint64, json_name: "sizeBytes"
  field :namespace, 4, type: :string
  field :media_type, 5, type: :string, json_name: "mediaType"
end

defmodule Once.Events.V1.RunEvent do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  oneof(:payload, 0)

  field :seq, 1, type: :uint64
  field :epoch_ms, 2, type: :int64, json_name: "epochMs"
  field :mono_ns, 3, type: :int64, json_name: "monoNs"
  field :run_started, 10, type: Once.Events.V1.RunStarted, json_name: "runStarted", oneof: 0

  field :run_finalizing, 11,
    type: Once.Events.V1.RunFinalizing,
    json_name: "runFinalizing",
    oneof: 0

  field :run_completed, 12, type: Once.Events.V1.RunCompleted, json_name: "runCompleted", oneof: 0
  field :run_heartbeat, 13, type: Once.Events.V1.RunHeartbeat, json_name: "runHeartbeat", oneof: 0

  field :graph_compiled, 20,
    type: Once.Events.V1.GraphCompiled,
    json_name: "graphCompiled",
    oneof: 0

  field :target_instance, 21,
    type: Once.Events.V1.TargetInstance,
    json_name: "targetInstance",
    oneof: 0

  field :target_queued, 30, type: Once.Events.V1.TargetQueued, json_name: "targetQueued", oneof: 0

  field :target_started, 31,
    type: Once.Events.V1.TargetStarted,
    json_name: "targetStarted",
    oneof: 0

  field :target_phase, 32, type: Once.Events.V1.TargetPhase, json_name: "targetPhase", oneof: 0
  field :target_wait, 33, type: Once.Events.V1.TargetWait, json_name: "targetWait", oneof: 0

  field :target_completed, 34,
    type: Once.Events.V1.TargetCompleted,
    json_name: "targetCompleted",
    oneof: 0

  field :target_cancelled, 35,
    type: Once.Events.V1.TargetCancelled,
    json_name: "targetCancelled",
    oneof: 0

  field :target_retried, 36,
    type: Once.Events.V1.TargetRetried,
    json_name: "targetRetried",
    oneof: 0

  field :action_completed, 37,
    type: Once.Events.V1.ActionCompleted,
    json_name: "actionCompleted",
    oneof: 0

  field :target_phase_completed, 38,
    type: Once.Events.V1.TargetPhaseCompleted,
    json_name: "targetPhaseCompleted",
    oneof: 0

  field :action_attempt_started, 39,
    type: Once.Events.V1.ActionAttemptStarted,
    json_name: "actionAttemptStarted",
    oneof: 0

  field :action_attempt_completed, 45,
    type: Once.Events.V1.ActionAttemptCompleted,
    json_name: "actionAttemptCompleted",
    oneof: 0

  field :test_suite_started, 40,
    type: Once.Events.V1.TestSuiteStarted,
    json_name: "testSuiteStarted",
    oneof: 0

  field :test_suite_completed, 41,
    type: Once.Events.V1.TestSuiteCompleted,
    json_name: "testSuiteCompleted",
    oneof: 0

  field :test_case_started, 42,
    type: Once.Events.V1.TestCaseStarted,
    json_name: "testCaseStarted",
    oneof: 0

  field :test_case_completed, 43,
    type: Once.Events.V1.TestCaseCompleted,
    json_name: "testCaseCompleted",
    oneof: 0

  field :test_case_retried, 44,
    type: Once.Events.V1.TestCaseRetried,
    json_name: "testCaseRetried",
    oneof: 0

  field :log_chunk, 50, type: Once.Events.V1.LogChunk, json_name: "logChunk", oneof: 0
  field :log_truncated, 51, type: Once.Events.V1.LogTruncated, json_name: "logTruncated", oneof: 0
  field :cache_probe, 60, type: Once.Events.V1.CacheProbe, json_name: "cacheProbe", oneof: 0

  field :cache_miss_reason, 61,
    type: Once.Events.V1.CacheMissReason,
    json_name: "cacheMissReason",
    oneof: 0

  field :cache_upload, 62, type: Once.Events.V1.CacheUpload, json_name: "cacheUpload", oneof: 0

  field :cache_download, 63,
    type: Once.Events.V1.CacheDownload,
    json_name: "cacheDownload",
    oneof: 0

  field :cache_store_reused, 64,
    type: Once.Events.V1.CacheStoreReused,
    json_name: "cacheStoreReused",
    oneof: 0

  field :artifact_published, 70,
    type: Once.Events.V1.ArtifactPublished,
    json_name: "artifactPublished",
    oneof: 0

  field :diagnostic_emitted, 71,
    type: Once.Events.V1.DiagnosticEmitted,
    json_name: "diagnosticEmitted",
    oneof: 0

  field :system_sampled, 80,
    type: Once.Events.V1.SystemSampled,
    json_name: "systemSampled",
    oneof: 0
end

defmodule Once.Events.V1.RunStarted do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :once_version, 1, type: :string, json_name: "onceVersion"
  field :protocol_version, 2, type: :string, json_name: "protocolVersion"
  field :host_class, 3, type: :string, json_name: "hostClass"
  field :git_rev, 4, type: :string, json_name: "gitRev"
  field :git_dirty, 5, type: :bool, json_name: "gitDirty"

  field :argv_normalized, 6,
    repeated: true,
    type: Once.Events.V1.ArgvToken,
    json_name: "argvNormalized"

  field :argv_hash_key_id, 7, type: :string, json_name: "argvHashKeyId"

  field :safe_literal_allowlist_version, 8,
    type: :string,
    json_name: "safeLiteralAllowlistVersion"

  field :cwd_relative, 9, type: :string, json_name: "cwdRelative"
  field :env_fingerprint, 10, type: :string, json_name: "envFingerprint"
  field :root_graph_digest, 11, type: Once.Events.V1.ContentRef, json_name: "rootGraphDigest"
  field :project_id, 12, type: :string, json_name: "projectId"
  field :effective_limits, 13, type: Once.Events.V1.EffectiveLimits, json_name: "effectiveLimits"
  field :is_ci, 14, type: :bool, json_name: "isCi"
  field :git_branch, 15, type: :string, json_name: "gitBranch"
end

defmodule Once.Events.V1.ArgvToken do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  oneof(:token, 0)

  field :safe_literal, 1, type: :string, json_name: "safeLiteral", oneof: 0
  field :flag_key, 2, type: :string, json_name: "flagKey", oneof: 0
  field :named_value, 3, type: Once.Events.V1.NamedValue, json_name: "namedValue", oneof: 0
  field :opaque_value_hash, 4, type: :string, json_name: "opaqueValueHash", oneof: 0
end

defmodule Once.Events.V1.NamedValue do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :key, 1, type: :string
  field :value_shape_hash, 2, type: :string, json_name: "valueShapeHash"
end

defmodule Once.Events.V1.EffectiveLimits do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :max_batch_bytes, 1, type: :uint32, json_name: "maxBatchBytes"
  field :max_event_bytes, 2, type: :uint32, json_name: "maxEventBytes"
  field :max_unacked_events, 3, type: :uint32, json_name: "maxUnackedEvents"
  field :max_log_chunk_bytes, 4, type: :uint32, json_name: "maxLogChunkBytes"
  field :log_ingestion_enabled, 5, type: :bool, json_name: "logIngestionEnabled"
  field :raw_event_retention_enabled, 6, type: :bool, json_name: "rawEventRetentionEnabled"
end

defmodule Once.Events.V1.RunFinalizing do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :declared_drain_ms, 1, type: :int64, json_name: "declaredDrainMs"
end

defmodule Once.Events.V1.RunCompleted do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :result, 1, type: Once.Events.V1.RunResult, enum: true
  field :cancellation_reason, 2, type: :string, json_name: "cancellationReason"
  field :wall_ms, 3, type: :int64, json_name: "wallMs"
  field :totals, 4, type: Once.Events.V1.RunTotals
  field :producer_dropped_events, 5, type: :uint64, json_name: "producerDroppedEvents"
end

defmodule Once.Events.V1.RunTotals.TargetsByResultEntry do
  @moduledoc false
  use Protobuf, map: true, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :uint32
end

defmodule Once.Events.V1.RunTotals.CasesByResultEntry do
  @moduledoc false
  use Protobuf, map: true, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :uint32
end

defmodule Once.Events.V1.RunTotals do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :targets_by_result, 1,
    repeated: true,
    type: Once.Events.V1.RunTotals.TargetsByResultEntry,
    json_name: "targetsByResult",
    map: true

  field :cases_by_result, 2,
    repeated: true,
    type: Once.Events.V1.RunTotals.CasesByResultEntry,
    json_name: "casesByResult",
    map: true

  field :cache_hit_rate, 3, type: :double, json_name: "cacheHitRate"
  field :cache_bytes_downloaded, 4, type: :uint64, json_name: "cacheBytesDownloaded"
  field :cache_bytes_uploaded, 5, type: :uint64, json_name: "cacheBytesUploaded"
  field :cache_bytes_saved, 6, type: :uint64, json_name: "cacheBytesSaved"
end

defmodule Once.Events.V1.RunHeartbeat do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3
end

defmodule Once.Events.V1.GraphCompiled.KindHistogramEntry do
  @moduledoc false
  use Protobuf, map: true, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :uint32
end

defmodule Once.Events.V1.GraphCompiled do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :graph_digest, 1, type: Once.Events.V1.ContentRef, json_name: "graphDigest"
  field :target_count, 2, type: :uint32, json_name: "targetCount"

  field :kind_histogram, 3,
    repeated: true,
    type: Once.Events.V1.GraphCompiled.KindHistogramEntry,
    json_name: "kindHistogram",
    map: true

  field :roots, 4, repeated: true, type: :string
end

defmodule Once.Events.V1.TargetInstance do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :target_instance_id, 1, type: :string, json_name: "targetInstanceId"
  field :target_id, 2, type: :string, json_name: "targetId"

  field :configuration_digest, 3,
    type: Once.Events.V1.ContentRef,
    json_name: "configurationDigest"
end

defmodule Once.Events.V1.TargetQueued do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  alias Once.Events.V1.ContentRef

  field :target_execution_id, 1, type: :string, json_name: "targetExecutionId"
  field :target_instance_id, 2, type: :string, json_name: "targetInstanceId"
  field :kind, 3, type: :string
  field :capability, 4, type: :string
  field :action_digest, 5, type: ContentRef, json_name: "actionDigest"
  field :input_digest, 6, type: ContentRef, json_name: "inputDigest"
  field :dep_target_executions, 7, repeated: true, type: :string, json_name: "depTargetExecutions"
  field :attempt, 8, type: :uint32
end

defmodule Once.Events.V1.TargetStarted do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :target_execution_id, 1, type: :string, json_name: "targetExecutionId"
  field :worker_class, 2, type: :string, json_name: "workerClass"
end

defmodule Once.Events.V1.TargetPhase do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :target_execution_id, 1, type: :string, json_name: "targetExecutionId"
  field :phase, 2, type: Once.Events.V1.Phase, enum: true
end

defmodule Once.Events.V1.TargetWait do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :target_execution_id, 1, type: :string, json_name: "targetExecutionId"
  field :reason, 2, type: Once.Events.V1.WaitReason, enum: true
  field :blocking_target_execution_id, 3, type: :string, json_name: "blockingTargetExecutionId"
  field :resource_kind, 4, type: :string, json_name: "resourceKind"
end

defmodule Once.Events.V1.TargetCompleted do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :target_execution_id, 1, type: :string, json_name: "targetExecutionId"
  field :result, 2, type: Once.Events.V1.TargetResult, enum: true
  field :was_cached, 3, type: :bool, json_name: "wasCached"
  field :exit_code, 4, proto3_optional: true, type: :int32, json_name: "exitCode"
  field :evidence_digest, 5, type: Once.Events.V1.ContentRef, json_name: "evidenceDigest"
  field :duration_ms, 6, type: :int64, json_name: "durationMs"
end

defmodule Once.Events.V1.TargetCancelled do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :target_execution_id, 1, type: :string, json_name: "targetExecutionId"
  field :reason, 2, type: :string
end

defmodule Once.Events.V1.TargetRetried do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :previous_target_execution_id, 1, type: :string, json_name: "previousTargetExecutionId"
  field :new_target_execution_id, 2, type: :string, json_name: "newTargetExecutionId"
  field :new_attempt, 3, type: :uint32, json_name: "newAttempt"
  field :reason, 4, type: :string
end

defmodule Once.Events.V1.ActionCompleted do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :target_execution_id, 1, type: :string, json_name: "targetExecutionId"
  field :capability, 2, type: :string
  field :action_index, 3, type: :uint32, json_name: "actionIndex"
  field :identifier, 4, type: :string
  field :result, 5, type: Once.Events.V1.TargetResult, enum: true
  field :was_cached, 6, type: :bool, json_name: "wasCached"
  field :duration_ms, 7, type: :int64, json_name: "durationMs"
  field :exit_code, 8, type: :int32, json_name: "exitCode"
  field :start_at_epoch_ms, 9, type: :int64, json_name: "startAtEpochMs"
  field :worker_id, 10, type: :string, json_name: "workerId"
  field :prepare_ms, 11, type: :int64, json_name: "prepareMs"
  field :execute_ms, 12, type: :int64, json_name: "executeMs"
  field :cache_key, 13, type: :string, json_name: "cacheKey"
  field :selected_attempt, 14, type: :uint32, json_name: "selectedAttempt"
end

defmodule Once.Events.V1.ActionAttemptStarted do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :target_execution_id, 1, type: :string, json_name: "targetExecutionId"
  field :capability, 2, type: :string
  field :action_index, 3, type: :uint32, json_name: "actionIndex"
  field :attempt, 4, type: :uint32
  field :worker_id, 5, type: :string, json_name: "workerId"
end

defmodule Once.Events.V1.ActionAttemptCompleted do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :target_execution_id, 1, type: :string, json_name: "targetExecutionId"
  field :capability, 2, type: :string
  field :action_index, 3, type: :uint32, json_name: "actionIndex"
  field :attempt, 4, type: :uint32
  field :result, 5, type: Once.Events.V1.TargetResult, enum: true
  field :exit_code, 6, type: :int32, json_name: "exitCode"
  field :duration_ms, 7, type: :int64, json_name: "durationMs"
  field :was_cached, 8, type: :bool, json_name: "wasCached"
end

defmodule Once.Events.V1.TargetPhaseCompleted do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :target_execution_id, 1, type: :string, json_name: "targetExecutionId"
  field :phase, 2, type: :string
  field :worker_id, 3, type: :string, json_name: "workerId"
  field :start_at_epoch_ms, 4, type: :int64, json_name: "startAtEpochMs"
  field :duration_ms, 5, type: :int64, json_name: "durationMs"
end

defmodule Once.Events.V1.TestSuiteStarted do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :target_execution_id, 1, type: :string, json_name: "targetExecutionId"
  field :suite_id, 2, type: :string, json_name: "suiteId"

  field :planned_case_count, 3,
    proto3_optional: true,
    type: :uint32,
    json_name: "plannedCaseCount"
end

defmodule Once.Events.V1.TestSuiteCompleted do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :target_execution_id, 1, type: :string, json_name: "targetExecutionId"
  field :suite_id, 2, type: :string, json_name: "suiteId"
  field :totals, 3, type: Once.Events.V1.TestTotals
  field :result_report_digest, 4, type: Once.Events.V1.ContentRef, json_name: "resultReportDigest"
end

defmodule Once.Events.V1.TestTotals do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :passed, 1, type: :uint32
  field :failed, 2, type: :uint32
  field :skipped, 3, type: :uint32
  field :errored, 4, type: :uint32
  field :timed_out, 5, type: :uint32, json_name: "timedOut"
  field :cancelled, 6, type: :uint32
  field :flaky_final_pass, 7, type: :uint32, json_name: "flakyFinalPass"
  field :flaky_final_fail, 8, type: :uint32, json_name: "flakyFinalFail"
  field :unknown, 9, type: :uint32
end

defmodule Once.Events.V1.TestCaseStarted do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :test_case_execution_id, 1, type: :string, json_name: "testCaseExecutionId"
  field :target_execution_id, 2, type: :string, json_name: "targetExecutionId"
  field :case_id, 3, type: :string, json_name: "caseId"
  field :name, 4, type: :string
  field :class_name, 5, type: :string, json_name: "className"
  field :file, 6, type: :string
  field :parameters, 7, type: :string
  field :tags, 8, repeated: true, type: :string
  field :attempt, 9, type: :uint32
end

defmodule Once.Events.V1.TestCaseCompleted do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :test_case_execution_id, 1, type: :string, json_name: "testCaseExecutionId"
  field :result, 2, type: Once.Events.V1.TestCaseResult, enum: true
  field :was_flaky, 3, type: :bool, json_name: "wasFlaky"
  field :duration_ms, 4, type: :int64, json_name: "durationMs"
  field :failure, 5, type: Once.Events.V1.TestFailure
  field :case_id, 6, type: :string, json_name: "caseId"
  field :name, 7, type: :string
  field :suite_id, 8, type: :string, json_name: "suiteId"
  field :attempt, 9, type: :uint32

  field :observed_duration_ms, 10,
    proto3_optional: true,
    type: :int64,
    json_name: "observedDurationMs"
end

defmodule Once.Events.V1.TestCaseRetried do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :previous_test_case_execution_id, 1,
    type: :string,
    json_name: "previousTestCaseExecutionId"

  field :new_test_case_execution_id, 2, type: :string, json_name: "newTestCaseExecutionId"
  field :new_attempt, 3, type: :uint32, json_name: "newAttempt"
  field :reason, 4, type: :string
end

defmodule Once.Events.V1.TestFailure do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :message, 1, type: :string
  field :expected, 2, type: :string
  field :actual, 3, type: :string
  field :stack_digest, 4, type: Once.Events.V1.ContentRef, json_name: "stackDigest"
end

defmodule Once.Events.V1.LogChunk do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :scope, 1, type: Once.Events.V1.LogScope
  field :stream, 2, type: Once.Events.V1.Stream, enum: true
  field :offset, 3, type: :int64
  field :bytes, 4, type: :bytes
end

defmodule Once.Events.V1.LogTruncated do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :scope, 1, type: Once.Events.V1.LogScope
  field :stream, 2, type: Once.Events.V1.Stream, enum: true
  field :bytes_dropped, 3, type: :int64, json_name: "bytesDropped"
  field :since_offset, 4, type: :int64, json_name: "sinceOffset"
end

defmodule Once.Events.V1.LogScope do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  oneof(:scope, 0)

  field :run, 1, type: Once.Events.V1.RunScope, oneof: 0
  field :target_execution_id, 2, type: :string, json_name: "targetExecutionId", oneof: 0
  field :test_case_execution_id, 3, type: :string, json_name: "testCaseExecutionId", oneof: 0
end

defmodule Once.Events.V1.RunScope do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3
end

defmodule Once.Events.V1.CacheProbe do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :cache_decision_id, 1, type: :string, json_name: "cacheDecisionId"
  field :target_execution_id, 2, type: :string, json_name: "targetExecutionId"
  field :action_digest, 3, type: Once.Events.V1.ContentRef, json_name: "actionDigest"
  field :tier, 4, type: :string
  field :tier_index, 5, type: :uint32, json_name: "tierIndex"
  field :outcome, 6, type: Once.Events.V1.CacheOutcome, enum: true
  field :duration_ms, 7, type: :int64, json_name: "durationMs"
  field :error_class, 8, type: :string, json_name: "errorClass"
end

defmodule Once.Events.V1.CacheMissReason do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  alias Once.Events.V1.MissReasonKind

  field :cache_decision_id, 1, type: :string, json_name: "cacheDecisionId"
  field :target_execution_id, 2, type: :string, json_name: "targetExecutionId"

  field :primary_reason, 3,
    type: MissReasonKind,
    json_name: "primaryReason",
    enum: true

  field :all_reasons, 4,
    repeated: true,
    type: MissReasonKind,
    json_name: "allReasons",
    enum: true

  field :analysis_status, 5,
    type: Once.Events.V1.MissAnalysisStatus,
    json_name: "analysisStatus",
    enum: true

  field :differing_inputs, 6, repeated: true, type: :string, json_name: "differingInputs"
  field :differing_inputs_total_count, 7, type: :uint32, json_name: "differingInputsTotalCount"
  field :differing_inputs_truncated, 8, type: :bool, json_name: "differingInputsTruncated"

  field :baseline_resolution, 9,
    type: Once.Events.V1.BaselineResolution,
    json_name: "baselineResolution"
end

defmodule Once.Events.V1.BaselineResolution do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  oneof(:kind, 0)

  field :reference, 1, type: Once.Events.V1.BaselineReference, oneof: 0

  field :none_available, 2,
    type: Once.Events.V1.BaselineNoneAvailable,
    json_name: "noneAvailable",
    oneof: 0

  field :not_attempted, 3,
    type: Once.Events.V1.BaselineNotAttempted,
    json_name: "notAttempted",
    oneof: 0

  field :unavailable, 4, type: Once.Events.V1.BaselineUnavailable, oneof: 0
end

defmodule Once.Events.V1.BaselineReference do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :previous_run_id, 1, type: :string, json_name: "previousRunId"
  field :previous_target_instance_id, 2, type: :string, json_name: "previousTargetInstanceId"
  field :previous_target_execution_id, 3, type: :string, json_name: "previousTargetExecutionId"

  field :previous_action_digest, 4,
    type: Once.Events.V1.ContentRef,
    json_name: "previousActionDigest"

  field :selection_reason, 5, type: :string, json_name: "selectionReason"
end

defmodule Once.Events.V1.BaselineNoneAvailable do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3
end

defmodule Once.Events.V1.BaselineNotAttempted do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :skip_reason, 1, type: :string, json_name: "skipReason"
end

defmodule Once.Events.V1.BaselineUnavailable do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :failure_reason, 1, type: :string, json_name: "failureReason"
end

defmodule Once.Events.V1.CacheUpload do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :cache_decision_id, 1, type: :string, json_name: "cacheDecisionId"
  field :target_execution_id, 2, type: :string, json_name: "targetExecutionId"
  field :content, 3, type: Once.Events.V1.ContentRef
  field :tier, 4, type: :string
  field :kind, 5, type: :string
  field :duration_ms, 6, type: :int64, json_name: "durationMs"
  field :bytes_transferred, 7, type: :uint64, json_name: "bytesTransferred"
end

defmodule Once.Events.V1.CacheDownload do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :cache_decision_id, 1, type: :string, json_name: "cacheDecisionId"
  field :target_execution_id, 2, type: :string, json_name: "targetExecutionId"
  field :content, 3, type: Once.Events.V1.ContentRef
  field :tier, 4, type: :string
  field :kind, 5, type: :string
  field :duration_ms, 6, type: :int64, json_name: "durationMs"
  field :bytes_transferred, 7, type: :uint64, json_name: "bytesTransferred"
end

defmodule Once.Events.V1.CacheStoreReused do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :cache_decision_id, 1, type: :string, json_name: "cacheDecisionId"
  field :target_execution_id, 2, type: :string, json_name: "targetExecutionId"
  field :content, 3, type: Once.Events.V1.ContentRef
  field :tier, 4, type: :string
  field :kind, 5, type: :string
  field :bytes_saved, 6, type: :uint64, json_name: "bytesSaved"
end

defmodule Once.Events.V1.ArtifactPublished do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :target_execution_id, 1, type: :string, json_name: "targetExecutionId"
  field :kind, 2, type: :string
  field :content, 3, type: Once.Events.V1.ContentRef
  field :workspace_relative_path, 4, type: :string, json_name: "workspaceRelativePath"
end

defmodule Once.Events.V1.DiagnosticEmitted do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  alias Once.Events.V1.Location

  field :target_execution_id, 1, type: :string, json_name: "targetExecutionId"
  field :severity, 2, type: Once.Events.V1.Severity, enum: true
  field :tool, 3, type: :string
  field :code, 4, type: :string
  field :message, 5, type: :string
  field :primary, 6, type: Location
  field :related, 7, repeated: true, type: Location
  field :fingerprint, 8, type: :string
  field :snippet, 9, type: Once.Events.V1.ContentRef
end

defmodule Once.Events.V1.Location do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :file, 1, type: :string
  field :start_line, 2, type: :uint32, json_name: "startLine"
  field :start_column, 3, type: :uint32, json_name: "startColumn"
  field :end_line, 4, type: :uint32, json_name: "endLine"
  field :end_column, 5, type: :uint32, json_name: "endColumn"
end

defmodule Once.Events.V1.SystemSampled do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :at_epoch_ms, 1, type: :int64, json_name: "atEpochMs"
  field :cpu_percent, 2, type: :float, json_name: "cpuPercent"
  field :memory_bytes, 3, type: :uint64, json_name: "memoryBytes"
  field :network_in_bytes_per_second, 4, type: :uint64, json_name: "networkInBytesPerSecond"
  field :network_out_bytes_per_second, 5, type: :uint64, json_name: "networkOutBytesPerSecond"
  field :resource_id, 6, type: :string, json_name: "resourceId"
  field :scope, 7, type: Once.Events.V1.ResourceScope, enum: true
  field :interval_ms, 8, type: :uint32, json_name: "intervalMs"
end

defmodule Once.Events.V1.RunEventService.Service do
  @moduledoc false

  use GRPC.Service, name: "once.events.v1.RunEventService", protoc_gen_elixir_version: "0.17.0"

  rpc(
    :GetServerCapabilities,
    Once.Events.V1.GetServerCapabilitiesRequest,
    Once.Events.V1.ServerCapabilities
  )

  rpc(:GetArgvHashKey, Once.Events.V1.GetArgvHashKeyRequest, Once.Events.V1.ArgvHashKey)

  rpc(:PublishRunEvents, stream(Once.Events.V1.RunEventBatch), stream(Once.Events.V1.BatchAck))

  rpc(:GetRunAck, Once.Events.V1.GetRunAckRequest, Once.Events.V1.RunEventAck)
end

defmodule Once.Events.V1.RunEventService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Once.Events.V1.RunEventService.Service
end
