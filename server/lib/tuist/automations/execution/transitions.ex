defmodule Tuist.Automations.Execution.Transitions do
  @moduledoc false
  import Ecto.Query

  alias Tuist.Automations
  alias Tuist.Automations.ActionExecutor
  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.Alerts.Event
  alias Tuist.Automations.Execution
  alias Tuist.Automations.Execution.Delivery
  alias Tuist.Automations.Execution.TestState
  alias Tuist.Automations.Execution.Transition
  alias Tuist.Automations.Workers.AutomationDeliveryWorker
  alias Tuist.Automations.Workers.TransitionFanoutWorker
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Tests

  def apply(transition_id) do
    case Repo.get(Transition, transition_id) do
      nil -> :ok
      transition -> Execution.with_lock("automation-state:#{transition.state_id}", fn -> apply_locked(transition_id) end)
    end
  end

  defp apply_locked(id) do
    transition = Repo.get!(Transition, id)
    state = Repo.get!(TestState, transition.state_id)
    alert = Repo.get!(Alert, state.alert_id)

    cond do
      transition.phase in ["applied", "cancelled"] ->
        :ok

      state.pending_transition_id != id ->
        {:snooze, 1}

      transition.phase == "failed" ->
        {:discard, :transition_failed}

      transition.phase == "pending" ->
        if alert.enabled and Execution.revision(alert) == transition.revision do
          prepare_and_apply(transition, state, alert)
        else
          cancel(transition, state)
        end

      transition.phase == "prepared" ->
        publish_and_commit(transition, state, alert)
    end
  end

  defp prepare_and_apply(transition, state, alert) do
    {attrs, _} = ActionExecutor.partition_actions(transition.actions, %{type: :test_case})
    config = if transition.status == "triggered", do: alert.trigger_config, else: alert.recovery_config
    eligible = Automations.filter_test_case_states([state.test_case_id], alert.project_id, config) != []

    if not eligible and transition.status == "triggered" do
      cancel(transition, state)
    else
      attrs = if eligible, do: attrs, else: %{}

      case Tests.prepare_automation_update(state.test_case_id, alert.project_id, attrs) do
        {:ok, snapshot, types} ->
          {:ok, prepared} = prepare(transition, alert, snapshot, types, eligible)
          if prepared, do: publish_and_commit(prepared, state, alert), else: cancel(transition, state)

        {:error, :not_found} ->
          cancel(transition, state)
      end
    end
  end

  defp prepare(transition, alert, snapshot, types, eligible) do
    # Authorization is a short transaction; the subsequent external write
    # may finish after an edit. Once prepared, retries must finish this
    # exact payload, rather than generating a later state mutation.
    Repo.transaction(fn ->
      current = Execution.locked_alert(alert.id)

      if current.enabled and Execution.revision(current) == transition.revision do
        Execution.update!(transition,
          phase: "prepared",
          snapshot: snapshot,
          event_types: types,
          occurred_at: DateTime.utc_now(),
          actions: if(eligible, do: transition.actions, else: [])
        )
      end
    end)
  end

  defp publish_and_commit(transition, state, alert) do
    events = events(transition, state, alert)
    :ok = Tests.write_automation_events(events, transition.id)
    at = DateTime.to_naive(transition.occurred_at)

    row = %{
      id: transition.id,
      alert_id: alert.id,
      baseline_generation: state.generation,
      test_case_id: state.test_case_id,
      status: transition.status,
      triggered_at: at,
      recovered_at: if(transition.status == "recovered", do: at),
      inserted_at: at
    }

    IngestRepo.insert_all(Event, [row], settings: [insert_deduplication_token: "automation-event:#{transition.id}"])

    {:ok, :ok} =
      Repo.transaction(fn ->
        current = Repo.one!(from(t in Transition, where: t.id == ^transition.id, lock: "FOR UPDATE"))

        if current.phase != "applied" do
          Execution.update!(current, phase: "applied", error: nil)
          state = Repo.one!(from(s in TestState, where: s.id == ^state.id, lock: "FOR UPDATE"))
          advance_state(state, transition, status: transition.status, triggered_at: transition.occurred_at)

          transition.actions
          |> Enum.with_index()
          |> Enum.each(fn
            {%{"type" => "send_slack"} = action, position} ->
              delivery = Repo.insert!(%Delivery{transition_id: transition.id, position: position, action: action})
              Oban.insert!(AutomationDeliveryWorker.new(%{delivery_id: delivery.id}))

            _ ->
              :ok
          end)

          Oban.insert!(TransitionFanoutWorker.new(%{transition_id: transition.id}))
        end

        :ok
      end)

    :ok
  end

  defp cancel(transition, state) do
    {:ok, _} =
      Repo.transaction(fn ->
        Execution.update!(transition, phase: "cancelled")
        state = Repo.one!(from(s in TestState, where: s.id == ^state.id, lock: "FOR UPDATE"))
        if state.pending_transition_id == transition.id, do: advance_state(state, transition, [])
      end)

    :ok
  end

  defp advance_state(state, transition, attrs) do
    next =
      Repo.one(
        from(t in Transition,
          where: t.state_id == ^state.id and t.sequence > ^transition.sequence,
          where: t.phase in ["pending", "prepared", "failed"],
          order_by: t.sequence,
          limit: 1,
          select: t.id
        )
      )

    Execution.update!(state, Keyword.put(attrs, :pending_transition_id, next))
  end

  def events(transition, state, alert) do
    Enum.map(transition.event_types, fn type ->
      %{
        id: event_id(transition.id, type),
        test_case_id: state.test_case_id,
        project_id: alert.project_id,
        event_type: type,
        actor_id: nil,
        alert_id: alert.id,
        inserted_at: DateTime.to_naive(transition.occurred_at)
      }
    end)
  end

  def event_id(id, type) do
    <<a::32, b::16, c::16, d::16, e::48, _::binary>> = :crypto.hash(:sha256, "#{id}:#{type}")
    Ecto.UUID.cast!(<<a::32, b::16, 4::4, c::12, 2::2, d::14, e::48>>)
  end

  def failure(id, final?) do
    # A prepared payload must remain resumable even after its job is discarded.
    # Its phase is retained; the persisted error and Oban row expose the failure.
    case Repo.get(Transition, id) do
      nil -> :ok
      transition -> Execution.update!(transition, error: if(final?, do: "attempts_exhausted", else: "attempt_failed"))
    end
  end
end
