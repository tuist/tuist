defmodule Tuist.Automations.Workers.AutomationDeliveryWorker do
  @moduledoc false
  use Oban.Worker, queue: :automation_deliveries, max_attempts: 12

  alias Tuist.Automations.Actions.SendSlackAction
  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.Execution
  alias Tuist.Automations.Execution.Delivery
  alias Tuist.Automations.Execution.TestState
  alias Tuist.Automations.Execution.Transition
  alias Tuist.Repo

  @impl Oban.Worker
  def timeout(_job), do: to_timeout(minute: 1)

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: min(5 * Integer.pow(2, min(attempt, 10)), 3600)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"delivery_id" => id}} = job) do
    case Repo.get(Delivery, id) do
      %Delivery{state: "pending"} = delivery ->
        # Channel identity coordinates webhook and bot deliveries across alerts,
        # accounts and replicas. A secret URL is never used as a database key.
        key = :sha256 |> :crypto.hash(delivery.action["channel"] || "unknown") |> Base.encode16(case: :lower)
        Execution.with_lock("automation-destination:#{key}", fn -> deliver(id, key, job) end)

      _ ->
        :ok
    end
  end

  defp deliver(id, key, job) do
    delivery = Repo.get!(Delivery, id)
    transition = Repo.get!(Transition, delivery.transition_id)
    state = Repo.get!(TestState, transition.state_id)
    alert = Repo.get!(Alert, state.alert_id)

    cond do
      delivery.state != "pending" ->
        :ok

      not alert.enabled or Execution.revision(alert) != transition.revision ->
        Execution.update!(delivery, state: "cancelled")
        :ok

      true ->
        case wait_seconds(key) do
          0 -> send_once(delivery, transition, alert, key, job)
          seconds -> {:snooze, seconds}
        end
    end
  end

  defp send_once(delivery, transition, alert, key, job) do
    snapshot = Map.new(transition.snapshot, fn {key, value} -> {String.to_existing_atom(key), value} end)
    delivery = Execution.update!(delivery, attempts: delivery.attempts + 1)
    result = SendSlackAction.deliver_once(alert, snapshot, delivery.action)

    delay =
      case result do
        {:snooze, seconds} -> seconds
        _ -> 1
      end

    # The session advisory lock spans the HTTP request and this cooldown write.
    # Other replicas never consume a slot while this destination is in flight.
    Repo.query!(
      "UPDATE automation_delivery_destinations SET available_at = clock_timestamp() + $2 * interval '1 second' WHERE key = $1",
      [key, delay]
    )

    case result do
      :ok ->
        Execution.update!(delivery, state: "delivered", error: nil)
        :ok

      {:snooze, _} ->
        Execution.update!(delivery, error: "rate_limited")
        result

      {:discard, reason} ->
        Execution.update!(delivery, state: "failed", error: Atom.to_string(reason))
        result

      {:error, reason} ->
        state = if job.attempt >= job.max_attempts, do: "failed", else: "pending"
        Execution.update!(delivery, state: state, error: Atom.to_string(reason))
        result
    end
  end

  defp wait_seconds(key) do
    Repo.query!(
      "INSERT INTO automation_delivery_destinations (key, available_at) VALUES ($1, clock_timestamp()) ON CONFLICT DO NOTHING",
      [key]
    )

    %{rows: [[seconds]]} =
      Repo.query!(
        "SELECT GREATEST(0, CEIL(EXTRACT(EPOCH FROM available_at - clock_timestamp())))::integer FROM automation_delivery_destinations WHERE key = $1",
        [key]
      )

    seconds
  end
end
