defmodule Tuist.Tests.Workers.SelectiveTestingCountsWorker do
  @moduledoc """
  Counts a test run's requested and skipped tests
  (`Tuist.Tests.SelectiveTestingCounts.record/1`) once the run and its command
  event are both stored. Both are written through buffers flushed on a tick,
  so the count waits that out. A count only reads and replaces the run's row,
  so a pending job absorbs a repeat, and one enqueued while another runs gets
  its own job.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:test_run_id], states: [:available, :scheduled], period: :infinity]

  alias Tuist.Environment
  alias Tuist.Tests.SelectiveTestingCounts

  def enqueue(test_run_id) when is_binary(test_run_id) and test_run_id != "" do
    %{test_run_id: test_run_id}
    |> new(schedule_in: div(Environment.clickhouse_flush_interval_ms(), 1000) + 5)
    |> Oban.insert()
  end

  def enqueue(_test_run_id), do: :skipped

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"test_run_id" => test_run_id}}) do
    SelectiveTestingCounts.record(test_run_id)
    :ok
  end
end
