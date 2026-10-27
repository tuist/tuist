defmodule Tuist.Tests.TestCase do
  @moduledoc """
  A test case represents a unique test identified by (name, module_name, suite_name, project_id).
  This is a ClickHouse entity that stores test case identity and latest run data.
  Uses ReplacingMergeTree to keep the most recent values for last_status, last_duration, last_ran_at.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  import Ecto.Changeset

  # The `duration_*` fields are alias fields, not columns:
  # `Tuist.Tests.list_test_cases/3` computes them with `selected_as/2` from the
  # per-case duration aggregates so the listing can sort by any of them.
  # `avg_duration` stays sortable for the public API and MCP tool, which expose
  # the denormalized column by name, and is why the aliases carry a
  # `duration_` prefix rather than colliding with it.
  #
  # `state` and `is_flaky` are deliberately absent from `filterable`. They live
  # in `test_case_states` (the columns of the same name here are legacy and no
  # longer read), so `Tuist.Tests.list_test_cases/3` pulls those filters out and
  # applies them against the joined subquery. Leaving them filterable here would
  # let a filter silently match the stale column instead.
  @derive {
    Flop.Schema,
    filterable: [
      :project_id,
      :name,
      :module_name,
      :suite_name,
      :last_status,
      :last_ran_at,
      :last_ran_at_ci,
      :last_ran_at_local
    ],
    sortable: [
      :name,
      :last_duration,
      :avg_duration,
      :duration_p50,
      :duration_p90,
      :duration_p99,
      :duration_avg,
      :last_ran_at,
      :id
    ],
    default_order: %{order_by: [:last_ran_at, :id], order_directions: [:desc, :asc]},
    adapter_opts: [alias_fields: [:duration_p50, :duration_p90, :duration_p99, :duration_avg]]
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
    field :last_ran_at_ci, Ch, type: "Nullable(DateTime64(6))"
    field :last_ran_at_local, Ch, type: "Nullable(DateTime64(6))"
    field :is_flaky, :boolean, default: false
    field :last_run_id, Ch, type: "Nullable(UUID)"
    field :state, Ch, type: "LowCardinality(String)"
    field :inserted_at, Ch, type: "DateTime64(6)"
    field :recent_durations, Ch, type: "Array(Int32)"
    field :avg_duration, Ch, type: "Int64"

    # Populated by `Tuist.Tests.list_test_cases/3` from
    # `test_case_duration_daily_stats_per_case`: the duration distribution over
    # the listing's active window in the selected environment. Each is `nil`
    # when `duration_sample_count` is below the minimum the listing requires for
    # them to mean anything. Each carries the value behind the alias field of
    # the same name minus `_ms`, named apart so it doesn't shadow the alias in
    # the derived `Flop.Schema` field list.
    field :duration_p50_ms, :float, virtual: true
    field :duration_p90_ms, :float, virtual: true
    field :duration_p99_ms, :float, virtual: true
    field :duration_avg_ms, :float, virtual: true
    field :duration_sample_count, :integer, virtual: true
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
      :last_ran_at_ci,
      :last_ran_at_local,
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
