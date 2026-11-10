defmodule Tuist.Automations.Workers.AlertEvaluationBatchWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :alert_evaluation_batches,
    max_attempts: 5,
    unique: [period: :infinity, states: [:available, :scheduled, :retryable]]

  alias Tuist.Automations
  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.Workers.AlertEvaluationWorker

  @batch_size 200

  @impl Oban.Worker
  def timeout(_job), do: to_timeout(minute: 4)

  def enqueue(alert, triggered_ids, scope, active_events) do
    active_events = active_events || Automations.list_active_alert_events(alert, scope)
    active_ids = MapSet.new(active_events, & &1.test_case_id)
    active_ids = if scope, do: MapSet.intersection(active_ids, MapSet.new(scope)), else: active_ids
    triggered_ids = MapSet.new(triggered_ids)

    # Include active tests whose condition may have cleared. Capture identifiers,
    # not decisions: queued batches re-read measurements and history when run.
    triggered_ids
    |> MapSet.symmetric_difference(active_ids)
    |> Enum.sort()
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(fn ids ->
      Oban.insert!(new(%{alert_id: alert.id, baseline_generation: alert.baseline_generation, test_case_ids: ids}))
    end)

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"alert_id" => id, "baseline_generation" => generation, "test_case_ids" => ids}})
      when length(ids) <= @batch_size do
    case Automations.get_alert(id) do
      {:ok, %Alert{enabled: true, baseline_generation: ^generation, baseline_established_at: at} = alert}
      when not is_nil(at) ->
        if Alert.recovery_ledger?(alert) and Alert.trigger_window_supported?(alert) do
          AlertEvaluationWorker.evaluate_batch(alert, ids)
        else
          :ok
        end

      _ ->
        :ok
    end
  end
end
