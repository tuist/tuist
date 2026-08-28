defmodule Tuist.Bazel.Invocation do
  @moduledoc false
  use Ecto.Schema

  @derive {
    Flop.Schema,
    filterable: [:project_id, :status, :command, :inserted_at],
    sortable: [:inserted_at, :started_at, :finished_at, :duration_ms, :command, :status],
    default_order: %{order_by: [:finished_at], order_directions: [:desc]}
  }

  @primary_key false
  schema "bazel_invocations" do
    field :id, Ch, type: "UUID"
    field :invocation_id, Ch, type: "String"
    field :command, Ch, type: "LowCardinality(String)"
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1)"
    field :exit_code, Ch, type: "Int32"
    field :started_at, Ch, type: "DateTime"
    field :finished_at, Ch, type: "DateTime"
    field :duration_ms, Ch, type: "UInt64"
    field :target_patterns, {:array, :string}
    field :requested_command, Ch, type: "String"
    field :original_command_line, {:array, :string}
    field :canonical_command_line, {:array, :string}
    field :bazel_version, Ch, type: "LowCardinality(String)"
    field :client_platform, Ch, type: "LowCardinality(String)"
    field :git_branch, Ch, type: "String"
    field :git_commit_sha, Ch, type: "String"
    field :configurations, {:array, :string}
    field :compilation_mode, Ch, type: "LowCardinality(String)"
    field :remote_cache_enabled, Ch, type: "Bool"
    field :remote_execution_enabled, Ch, type: "Bool"
    field :cpu_time_ms, Ch, type: "UInt64"
    field :actions_executed, Ch, type: "UInt64"
    field :targets_loaded, Ch, type: "UInt64"
    field :targets_configured, Ch, type: "UInt64"
    field :packages_loaded, Ch, type: "UInt64"
    field :build_timeline_duration_ms, Ch, type: "UInt64"
    field :build_timeline_lanes, {:array, :string}
    field :build_timeline_span_lanes, {:array, Ch}, type: "UInt8", default: []
    field :build_timeline_span_start_ms, {:array, Ch}, type: "UInt64", default: []
    field :build_timeline_span_durations_ms, {:array, Ch}, type: "UInt64", default: []
    field :build_timeline_span_categories, {:array, Ch}, type: "LowCardinality(String)", default: []
    field :build_timeline_span_descriptions, {:array, Ch}, type: "String", default: []
    field :critical_path_duration_ms, Ch, type: "UInt64"
    field :critical_path_action_descriptions, {:array, Ch}, type: "String", default: []
    field :critical_path_action_durations_ms, {:array, Ch}, type: "UInt64", default: []
    field :project_id, Ch, type: "Int64"
    field :account_handle, Ch, type: "String"
    field :project_handle, Ch, type: "String"
    field :cache_endpoint, Ch, type: "LowCardinality(String)"
    field :inserted_at, Ch, type: "DateTime"
  end
end
