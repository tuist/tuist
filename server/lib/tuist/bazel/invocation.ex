defmodule Tuist.Bazel.Invocation do
  @moduledoc false
  use Ecto.Schema

  @derive {
    Flop.Schema,
    filterable: [:project_id, :status, :command, :inserted_at],
    sortable: [:inserted_at, :started_at, :finished_at, :duration_ms, :status, :command],
    default_order: %{order_by: [:finished_at], order_directions: [:desc]}
  }

  @primary_key false
  schema "bazel_invocations" do
    field :id, Ch, type: "UUID"
    field :invocation_id, Ch, type: "String"
    field :command, Ch, type: "LowCardinality(String)"
    field :target_patterns, {:array, Ch}, type: "String", default: []
    field :git_branch, Ch, type: "String", default: ""
    field :git_commit_sha, Ch, type: "String", default: ""
    field :is_ci, :boolean, default: false
    field :bazel_version, Ch, type: "LowCardinality(String)", default: ""
    field :cpu_time_ms, Ch, type: "UInt64", default: 0
    field :actions_created, Ch, type: "UInt64", default: 0
    field :actions_executed, Ch, type: "UInt64", default: 0
    field :targets_configured, Ch, type: "UInt64", default: 0
    field :packages_loaded, Ch, type: "UInt64", default: 0
    field :build_timeline_duration_ms, Ch, type: "UInt64", default: 0
    field :build_timeline_lanes, {:array, Ch}, type: "String", default: []
    field :build_timeline_span_lanes, {:array, Ch}, type: "UInt8", default: []
    field :build_timeline_span_start_ms, {:array, Ch}, type: "UInt64", default: []
    field :build_timeline_span_durations_ms, {:array, Ch}, type: "UInt64", default: []
    field :build_timeline_span_categories, {:array, Ch}, type: "LowCardinality(String)", default: []
    field :build_timeline_span_descriptions, {:array, Ch}, type: "String", default: []
    field :critical_path_duration_ms, Ch, type: "UInt64", default: 0
    field :critical_path_action_descriptions, {:array, Ch}, type: "String", default: []
    field :critical_path_action_durations_ms, {:array, Ch}, type: "UInt64", default: []
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1)"
    field :exit_code, Ch, type: "Int32"
    field :started_at, Ch, type: "DateTime"
    field :finished_at, Ch, type: "DateTime"
    field :duration_ms, Ch, type: "UInt64"
    field :project_id, Ch, type: "Int64"
    field :account_handle, Ch, type: "String"
    field :project_handle, Ch, type: "String"
    field :cache_endpoint, Ch, type: "LowCardinality(String)"
    field :inserted_at, Ch, type: "DateTime"
  end
end
