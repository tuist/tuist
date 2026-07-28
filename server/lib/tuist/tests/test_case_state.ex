defmodule Tuist.Tests.TestCaseState do
  @moduledoc """
  Control-plane state for a test case: whether it's muted/skipped and whether
  it's flagged flaky.

  These used to be columns on `test_cases`, but that table is rewritten
  wholesale by test-report ingestion, which snapshots the existing row before
  it writes. A mute landing inside that window was overwritten by an ingestion
  row carrying the pre-mute value with a higher version.

  Nothing in the application writes this table. It is a projection of
  `test_case_events`, maintained by the `test_case_states_mv` materialized
  view, so the event ledger is the only source of truth and there is no second
  writer to disagree with it.

  Each row records the one column its event affected and leaves the other NULL,
  because `state` and `is_flaky` move independently. Reads resolve each column
  with its own `argMaxIf(..., isNotNull(...))`; see
  `Tuist.Tests.resolve_test_case_state/2`. A test case with no rows here has
  never been muted, skipped, or flagged, and falls back to the defaults.
  """
  use Ecto.Schema

  @primary_key false
  schema "test_case_states" do
    field :project_id, Ch, type: "Int64"
    field :test_case_id, Ecto.UUID
    field :state, Ch, type: "LowCardinality(Nullable(String))"
    field :is_flaky, Ch, type: "Nullable(Bool)"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
