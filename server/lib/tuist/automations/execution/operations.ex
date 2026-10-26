defmodule Tuist.Automations.Execution.Operations do
  @moduledoc "Administrative inspection, replay and bounded retention for automation execution."
  import Ecto.Query

  alias Tuist.Automations.Execution
  alias Tuist.Automations.Execution.Delivery
  alias Tuist.Automations.Execution.Evaluation
  alias Tuist.Automations.Execution.TestState
  alias Tuist.Automations.Execution.Transition
  alias Tuist.Automations.Workers.AutomationDeliveryWorker
  alias Tuist.Automations.Workers.EvaluationPageWorker
  alias Tuist.Automations.Workers.TransitionFanoutWorker
  alias Tuist.Automations.Workers.TransitionWorker
  alias Tuist.Repo

  # Operator-only entry points, not exposed through a tenant-facing transport.
  def status(alert_id) do
    %{
      evaluations:
        Repo.all(
          from(e in Evaluation,
            where: e.alert_id == ^alert_id,
            group_by: e.state,
            select: %{state: e.state, count: count(), oldest: min(e.inserted_at)}
          )
        ),
      transitions:
        Repo.all(
          from(t in Transition,
            join: s in TestState,
            on: s.id == t.state_id,
            where: s.alert_id == ^alert_id,
            group_by: [t.phase, t.error],
            select: %{phase: t.phase, error: t.error, count: count(), oldest: min(t.inserted_at)}
          )
        ),
      deliveries:
        Repo.all(
          from(d in Delivery,
            join: t in Transition,
            on: t.id == d.transition_id,
            join: s in TestState,
            on: s.id == t.state_id,
            where: s.alert_id == ^alert_id,
            group_by: [d.state, d.error],
            select: %{
              state: d.state,
              error: d.error,
              count: count(),
              attempts: sum(d.attempts),
              oldest: min(d.inserted_at)
            }
          )
        )
    }
  end

  def retry_evaluation(id),
    do: retry(Evaluation, id, EvaluationPageWorker, :evaluation_id, fn run -> run.state == "running" end)

  def retry_transition(id),
    do: retry(Transition, id, TransitionWorker, :transition_id, fn t -> t.phase in ["pending", "prepared"] end)

  def retry_fanout(id),
    do:
      retry(Transition, id, TransitionFanoutWorker, :transition_id, fn t -> t.phase == "applied" and not t.fanout_done end)

  def retry_delivery(id) do
    Repo.transaction(fn ->
      delivery = Repo.one!(from(d in Delivery, where: d.id == ^id, lock: "FOR UPDATE"))
      if delivery.state not in ["pending", "failed"], do: Repo.rollback(:already_finished)
      Execution.update!(delivery, state: "pending", error: nil)
      Oban.insert!(AutomationDeliveryWorker.new(%{delivery_id: id}, unique: [period: :infinity, states: :incomplete]))
    end)
  end

  defp retry(schema, id, worker, key, eligible) do
    Repo.transaction(fn ->
      record = Repo.one!(from(r in schema, where: r.id == ^id, lock: "FOR UPDATE"))
      if !eligible.(record), do: Repo.rollback(:already_finished)
      Oban.insert!(worker.new(%{key => id}, unique: [period: :infinity, states: :incomplete]))
    end)
  end

  def prune do
    cutoff = DateTime.add(DateTime.utc_now(), -30, :day)

    evaluations =
      from(e in Evaluation,
        where: e.state != "running" and e.updated_at < ^cutoff,
        order_by: e.id,
        limit: 500,
        select: e.id
      )

    Repo.delete_all(from(e in Evaluation, where: e.id in subquery(evaluations)))

    transitions =
      from(t in Transition,
        as: :transition,
        where: t.updated_at < ^cutoff,
        where: t.phase == "cancelled" or (t.phase == "applied" and t.fanout_done),
        where:
          not exists(
            from(d in Delivery, where: d.transition_id == parent_as(:transition).id and d.state in ["pending", "failed"])
          ),
        order_by: t.id,
        limit: 500,
        select: t.id
      )

    Repo.delete_all(from(t in Transition, where: t.id in subquery(transitions)))
    :ok
  end
end
