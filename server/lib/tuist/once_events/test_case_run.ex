defmodule Tuist.OnceEvents.TestCaseRun do
  @moduledoc """
  One attempt of one test case executed under an Once run.
  Streamed on `TestCaseCompleted`: every completion inserts a row so
  the Tests page can render results as they arrive rather than
  waiting for the suite to finish.

  Unique per `(once_run_id, case_id, attempt)` so a retried case
  produces a new row on each attempt instead of overwriting the
  first one.
  """
  use Ecto.Schema

  alias Tuist.OnceEvents.Run

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "once_test_case_runs" do
    belongs_to :run, Run, foreign_key: :once_run_id, type: UUIDv7
    field :run_id, :string
    field :project_id, :integer

    field :target_execution_id, :string
    field :suite_id, :string

    field :case_id, :string
    field :name, :string
    field :class_name, :string
    field :module, :string

    field :attempt, :integer, default: 1

    field :result, :string
    field :duration_ms, :integer, default: 0
    field :failure_message, :string
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    # Event ingest orders rows by these, and a run emits many events per
    # millisecond, so the microsecond precision is load bearing.
    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(type: :utc_datetime_usec)
  end
end
