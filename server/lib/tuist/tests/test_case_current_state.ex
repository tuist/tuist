defmodule Tuist.Tests.TestCaseCurrentState do
  @moduledoc """
  Ecto schema for the `test_case_current_states` ClickHouse table.

  AggregatingMergeTree keyed on `(project_id, test_case_id)` holding `argMaxIf`
  aggregate states for `state` and `is_flaky`, maintained by
  `test_case_current_states_mv` off the `test_case_states` ledger. It is the
  pre-aggregated form of the per-column-nullable resolution the readers in
  `Tuist.Tests` used to compute at query time against the raw ledger.

  Only the dimension columns are declared. The aggregate state columns are read
  through `fragment("argMaxIfMerge(?)", ...)` in queries, since Ecto has no type
  mapping for ClickHouse `AggregateFunction` types. Every read must go through
  that merge with a `GROUP BY (project_id, test_case_id)`: partial states are
  not merged synchronously, so a key can have several unmerged rows.
  """
  use Ecto.Schema

  @primary_key false
  schema "test_case_current_states" do
    field :project_id, Ch, type: "Int64"
    field :test_case_id, Ecto.UUID
  end
end
