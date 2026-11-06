defmodule Atlas.Engineering.Alerts.Workers.EvaluateSpikes do
  @moduledoc "Evaluates committed error windows once a minute, independently of ingest buffers."

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 60, states: :incomplete]

  import Ecto.Query

  alias Atlas.Engineering.Alerts
  alias Atlas.Engineering.Alerts.Rule
  alias Atlas.Engineering.Alerts.Workers.DeliverRule
  alias Atlas.Engineering.Errors
  alias Atlas.Repo

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"rule_id" => id}}) do
    if Errors.enabled?() do
      case Repo.one(from(rule in Rule, where: rule.id == ^id and rule.enabled and rule.trigger == :event_spike)) do
        nil -> :ok
        rule -> evaluate_rule(rule)
      end
    else
      :ok
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Errors.enabled?() do
      # Only schedule inside the coordination transaction. Event-storage reads
      # run in independent jobs so a slow rule cannot roll back healthy ones.
      case Repo.transaction(&evaluate_locked/0) do
        {:ok, result} -> result
        {:error, _} = error -> error
      end
    else
      :ok
    end
  end

  defp evaluate_locked do
    case Repo.query!("SELECT pg_try_advisory_xact_lock(hashtext($1))", ["atlas.alert.spike_evaluation"]) do
      %{rows: [[true]]} ->
        rules = Repo.all(from(rule in Rule, where: rule.enabled and rule.trigger == :event_spike))
        Enum.each(rules, fn rule -> Oban.insert!(new(%{"rule_id" => rule.id})) end)
        :ok

      %{rows: [[false]]} ->
        :ok
    end
  end

  defp evaluate_rule(rule) do
    case Alerts.spike_matches(rule, DateTime.utc_now()) do
      {:ok, matches} ->
        Enum.each(matches, &enqueue(rule, &1))
        :ok

      {:error, _} = error ->
        error
    end
  end

  defp enqueue(rule, match) do
    %{
      "rule_id" => rule.id,
      "subject_type" => "error_issue",
      "subject_id" => match.issue_id,
      "reason" => "event_spike",
      "environment" => rule.environment
    }
    |> DeliverRule.new(unique: [period: 60, keys: [:rule_id, :subject_id]])
    |> Oban.insert!()
  end
end
