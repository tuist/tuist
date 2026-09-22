defmodule Tuist.OnceEvents.TestSuiteRun do
  @moduledoc """
  One test suite executed under an Once run. Rolls up per-case
  counts so the Tests page can render suite-level summaries without
  scanning every `TestCaseRun`.

  Unique per `(once_run_id, target_execution_id, suite_id)` so
  reruns of the same suite in the same invocation keep merging into
  one row while distinct suites under the same target stay
  separate.
  """
  use Ecto.Schema

  alias Tuist.OnceEvents.Run

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "once_test_suite_runs" do
    belongs_to :run, Run, foreign_key: :once_run_id, type: UUIDv7
    field :run_id, :string
    field :project_id, :integer

    field :target_execution_id, :string
    field :suite_id, :string

    field :planned_case_count, :integer

    field :total_cases, :integer, default: 0
    field :passed_cases, :integer, default: 0
    field :failed_cases, :integer, default: 0
    field :skipped_cases, :integer, default: 0
    field :errored_cases, :integer, default: 0
    field :timed_out_cases, :integer, default: 0
    field :cancelled_cases, :integer, default: 0

    field :duration_ms, :integer, default: 0
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
