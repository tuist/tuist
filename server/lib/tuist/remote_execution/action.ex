defmodule Tuist.RemoteExecution.Action do
  @moduledoc """
  An action the execution gateway ran remotely, as the gateway reported it
  after the client had its result. See `Tuist.RemoteExecution.Actions`.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "remote_execution_actions" do
    field :operation_id, Ch, type: "UUID"
    field :account_id, Ch, type: "Int64"
    field :project_id, Ch, type: "Int64"
    field :invocation_id, :string
    field :action_hash, :string
    field :action_size, Ch, type: "Int64"
    field :tool_name, Ch, type: "LowCardinality(String)"
    field :tool_version, Ch, type: "LowCardinality(String)"
    field :mnemonic, Ch, type: "LowCardinality(String)"
    field :target, :string
    field :configuration_id, :string
    field :execution_path, Ch, type: "LowCardinality(String)"
    field :sandbox_id, :string
    field :worker, :string
    field :memory_gb, Ch, type: "UInt16"
    field :timeout_ms, Ch, type: "UInt64"
    field :do_not_cache, Ch, type: "Bool"
    field :cached_result, Ch, type: "Bool"
    field :arguments, Ch, type: "Array(String)", default: []
    field :arguments_truncated, Ch, type: "Bool"
    field :environment_names, Ch, type: "Array(String)", default: []
    field :environment_values, Ch, type: "Array(String)", default: []
    field :working_directory, :string
    field :platform_names, Ch, type: "Array(String)", default: []
    field :platform_values, Ch, type: "Array(String)", default: []
    field :output_paths, Ch, type: "Array(String)", default: []
    field :output_count, Ch, type: "UInt32", default: 0
    field :status_code, Ch, type: "Int32"
    field :status_message, :string
    field :exit_code, Ch, type: "Int32"
    field :queued_at, Ch, type: "Nullable(DateTime64(6))"
    field :worker_start_at, Ch, type: "Nullable(DateTime64(6))"
    field :input_fetch_start_at, Ch, type: "Nullable(DateTime64(6))"
    field :input_fetch_completed_at, Ch, type: "Nullable(DateTime64(6))"
    field :execution_start_at, Ch, type: "Nullable(DateTime64(6))"
    field :execution_completed_at, Ch, type: "Nullable(DateTime64(6))"
    field :output_upload_start_at, Ch, type: "Nullable(DateTime64(6))"
    field :output_upload_completed_at, Ch, type: "Nullable(DateTime64(6))"
    field :worker_completed_at, Ch, type: "Nullable(DateTime64(6))"
    field :stdout, :string
    field :stdout_size, Ch, type: "UInt64"
    field :stdout_truncated, Ch, type: "Bool"
    field :stderr, :string
    field :stderr_size, Ch, type: "UInt64"
    field :stderr_truncated, Ch, type: "Bool"
    field :inserted_at, Ch, type: "DateTime64(6)"
    # Copied from the Struo run the invocation ID names; nil when unknown.
    field :is_ci, Ch, type: "Nullable(Bool)"
  end
end
