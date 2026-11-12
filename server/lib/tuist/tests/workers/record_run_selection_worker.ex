defmodule Tuist.Tests.Workers.RecordRunSelectionWorker do
  @moduledoc """
  Records how many tests a test run's selection avoided
  (`Tuist.Tests.RunSelections.record_run/2`), queued when the run's command
  event or test run arrives. Either can come first: a command event names a
  run the xcresult processor may still be writing, so a run that isn't stored
  yet is waited for, a day at most.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [keys: [:test_run_id], states: [:available, :scheduled], period: :infinity]

  alias Tuist.Tests.RunSelections

  @run_wait_seconds 86_400
  @snooze_seconds 120

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "test_run_id" => test_run_id}, inserted_at: inserted_at}) do
    case RunSelections.record_run(project_id, test_run_id) do
      :ok ->
        :ok

      {:pending, seconds} ->
        {:snooze, seconds}

      :not_found ->
        if DateTime.diff(DateTime.utc_now(), inserted_at, :second) < @run_wait_seconds,
          do: {:snooze, @snooze_seconds},
          else: :ok
    end
  end
end
