defmodule Tuist.Bazel.TestResult do
  @moduledoc false
  use Ecto.Schema

  @derive {
    Flop.Schema,
    filterable: [:project_id, :status, :target_label, :invocation_id, :inserted_at],
    sortable: [:inserted_at, :finished_at, :duration_ms, :status, :target_label, :invocation_id, :attempt_count],
    default_order: %{order_by: [:finished_at], order_directions: [:desc]}
  }

  @primary_key false
  schema "bazel_test_results" do
    field :id, Ch, type: "UUID"
    field :invocation_id, Ch, type: "String"
    field :target_label, Ch, type: "String"
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1, 'flaky' = 2, 'skipped' = 3)"
    field :duration_ms, Ch, type: "UInt64"
    field :attempt_count, Ch, type: "UInt32"
    field :finished_at, Ch, type: "DateTime"
    field :project_id, Ch, type: "Int64"
    field :account_handle, Ch, type: "String"
    field :project_handle, Ch, type: "String"
    field :cache_endpoint, Ch, type: "LowCardinality(String)"
    field :inserted_at, Ch, type: "DateTime"
  end
end
