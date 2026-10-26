defmodule Tuist.Automations.Workers.TransitionFanoutWorker do
  @moduledoc false
  use Oban.Worker, queue: :automation_transitions, max_attempts: 10

  import Ecto.Query

  alias Tuist.Automations
  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Automations.Execution
  alias Tuist.Automations.Execution.TestState
  alias Tuist.Automations.Execution.Transition
  alias Tuist.Automations.Execution.Transitions
  alias Tuist.MCP.Events.Publisher
  alias Tuist.Repo
  alias Tuist.Tests
  alias Tuist.Webhooks.Dispatcher

  @impl Oban.Worker
  def timeout(_job), do: to_timeout(minute: 2)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"transition_id" => id}}) do
    {:ok, result} =
      Repo.transaction(fn ->
        case Repo.one(from(t in Transition, where: t.id == ^id, lock: "FOR UPDATE")) do
          %Transition{phase: "applied", fanout_done: false} = transition ->
            fanout(transition)

          %Transition{phase: "applied"} = transition ->
            transition

          _ ->
            :ok
        end
      end)

    if match?(%Transition{event_types: [_ | _]}, result) do
      state = Repo.get!(TestState, result.state_id)
      Tests.broadcast_automation_update(state.test_case_id, Enum.map(result.event_types, &String.to_existing_atom/1))
    end

    :ok
  end

  defp fanout(transition) do
    state = Repo.get!(TestState, transition.state_id)
    alert = Repo.get!(Alert, state.alert_id)
    snapshot = Map.new(transition.snapshot, fn {key, value} -> {String.to_existing_atom(key), value} end)
    types = Enum.map(transition.event_types, &String.to_existing_atom/1)

    if types != [] do
      :ok =
        Dispatcher.dispatch_test_case_event(snapshot, types,
          alert_id: alert.id,
          event_id: transition.id,
          occurred_at: transition.occurred_at,
          strict: true
        )
    end

    Enum.each(Transitions.events(transition, state, alert), fn event ->
      Automations.enqueue_test_case_event(String.to_existing_atom(event.event_type), snapshot, event.id, transition.depth)

      if event.event_type == "marked_flaky" do
        :ok =
          Publisher.publish!(
            "test_case.marked_flaky",
            %{"project_id" => alert.project_id, "test_case_id" => state.test_case_id},
            event.id
          )
      end
    end)

    Execution.update!(transition, fanout_done: true)
  end
end
