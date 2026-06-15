defmodule Tuist.Tests.Workers.FlakyTestsByHashWorker do
  @moduledoc """
  Runs hash-based flaky-test detection for a finished test run.

  Enqueued from command-event ingestion once the command event (and its
  `xcode_targets` selective-testing hashes) exist. Scheduled slightly past
  the ClickHouse buffer flush so the run's `test_case_runs` are queryable by
  the time it runs.
  """
  use Oban.Worker, max_attempts: 3, queue: :default

  alias Tuist.CommandEvents
  alias Tuist.Environment
  alias Tuist.Tests

  def enqueue(command_event_id, test_run_id) do
    %{command_event_id: command_event_id, test_run_id: test_run_id}
    |> new(schedule_in: schedule_in())
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"command_event_id" => command_event_id, "test_run_id" => test_run_id}}) do
    case CommandEvents.get_command_event_by_id(command_event_id) do
      {:ok, command_event} -> Tests.detect_flaky_tests_by_hash(command_event, test_run_id)
      {:error, :not_found} -> :ok
    end
  end

  # Mirror the alert evaluator: wait for the buffer flush plus a small margin
  # so the just-ingested `test_case_runs` are visible.
  defp schedule_in, do: div(Environment.clickhouse_flush_interval_ms(), 1000) + 5
end
