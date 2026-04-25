defmodule Tuist.Tests.TestCase do
  @moduledoc """
  A test case represents a unique test identified by (name, module_name, suite_name, project_id).
  This is a ClickHouse entity that stores test case identity and latest run data.
  Uses ReplacingMergeTree to keep the most recent values for last_status, last_duration, last_ran_at.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [
      :project_id,
      :name,
      :module_name,
      :suite_name,
      :last_status,
      :is_flaky,
      :state
    ],
    sortable: [:name, :last_duration, :avg_duration, :last_ran_at, :id],
    default_order: %{order_by: [:last_ran_at, :id], order_directions: [:desc, :asc]}
  }

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_cases" do
    field :name, :string
    field :module_name, :string
    field :suite_name, :string
    field :project_id, Ch, type: "Int64"
    field :last_status, Ch, type: "Enum8('success' = 0, 'failure' = 1, 'skipped' = 2)"
    field :last_duration, Ch, type: "Int32"
    field :last_ran_at, Ch, type: "DateTime64(6)"
    field :is_flaky, :boolean, default: false
    field :last_run_id, Ch, type: "Nullable(UUID)"
    field :state, Ch, type: "LowCardinality(String)"
    field :inserted_at, Ch, type: "DateTime64(6)"
    field :recent_durations, Ch, type: "Array(Int32)"
    field :avg_duration, Ch, type: "Int64"
  end

  def create_changeset(test_case, attrs) do
    test_case
    |> cast(attrs, [
      :id,
      :name,
      :module_name,
      :suite_name,
      :project_id,
      :last_status,
      :last_duration,
      :last_ran_at,
      :is_flaky,
      :last_run_id,
      :state,
      :inserted_at,
      :recent_durations,
      :avg_duration
    ])
    |> validate_required([:id, :name, :module_name, :suite_name, :project_id, :last_status, :last_duration, :last_ran_at])
  end
end
