defmodule Tuist.Alerts do
  @moduledoc """
  Context module for managing alerts and alert rules.
  """
  import Ecto.Query

  alias Tuist.Alerts.Alert
  alias Tuist.Alerts.AlertRule
  alias Tuist.Repo
  alias Tuist.Runs.Analytics

  # AlertRule CRUD functions

  def list_project_alert_rules(project_id) do
    AlertRule
    |> where([a], a.project_id == ^project_id)
    |> order_by([a], asc: a.inserted_at)
    |> Repo.all()
  end

  def get_alert_rule(id) do
    case Repo.get(AlertRule, id) do
      nil -> {:error, :not_found}
      alert_rule -> {:ok, alert_rule}
    end
  end

  def create_alert_rule(attrs) do
    %AlertRule{}
    |> AlertRule.changeset(attrs)
    |> Repo.insert()
  end

  def update_alert_rule(%AlertRule{} = alert_rule, attrs) do
    alert_rule
    |> AlertRule.changeset(attrs)
    |> Repo.update()
  end

  def delete_alert_rule(%AlertRule{} = alert_rule) do
    Repo.delete(alert_rule)
  end

  def list_enabled_alert_rules do
    AlertRule
    |> where([a], a.enabled == true)
    |> Repo.all()
    |> Repo.preload(project: [account: :slack_installation])
  end

  def update_alert_rule_triggered_at(%AlertRule{} = alert_rule) do
    alert_rule
    |> Ecto.Changeset.change(last_triggered_at: DateTime.truncate(DateTime.utc_now(), :second))
    |> Repo.update()
  end

  def cooldown_elapsed?(%AlertRule{last_triggered_at: nil}), do: true

  def cooldown_elapsed?(%AlertRule{last_triggered_at: last_triggered}) do
    hours_since = DateTime.diff(DateTime.utc_now(), last_triggered, :hour)
    hours_since >= 24
  end

  # Alert evaluation

  @doc """
  Evaluates an alert rule and returns a triggered Alert if threshold exceeded.

  The alert_rule must have project and account preloaded.

  Returns:
  - `{:triggered, alert}` if threshold exceeded
  - `:ok` if no alert needed
  """
  def evaluate(%AlertRule{category: :build_run_duration, project: project} = alert_rule) do
    sample_size = alert_rule.sample_size
    metric = alert_rule.metric

    current = Analytics.build_duration_metric_by_count(project.id, metric, limit: sample_size, offset: 0)
    previous = Analytics.build_duration_metric_by_count(project.id, metric, limit: sample_size, offset: sample_size)

    check_increase_regression(alert_rule, current, previous)
  end

  def evaluate(%AlertRule{category: :test_run_duration, project: project} = alert_rule) do
    sample_size = alert_rule.sample_size
    metric = alert_rule.metric

    current = Analytics.test_duration_metric_by_count(project.id, metric, limit: sample_size, offset: 0)
    previous = Analytics.test_duration_metric_by_count(project.id, metric, limit: sample_size, offset: sample_size)

    check_increase_regression(alert_rule, current, previous)
  end

  def evaluate(%AlertRule{category: :cache_hit_rate, project: project} = alert_rule) do
    sample_size = alert_rule.sample_size
    metric = alert_rule.metric

    current = Analytics.build_cache_hit_rate_metric_by_count(project.id, metric, limit: sample_size, offset: 0)
    previous = Analytics.build_cache_hit_rate_metric_by_count(project.id, metric, limit: sample_size, offset: sample_size)

    check_decrease_regression(alert_rule, current, previous)
  end

  defp check_increase_regression(_alert_rule, nil, _), do: :ok
  defp check_increase_regression(_alert_rule, _, nil), do: :ok
  defp check_increase_regression(_alert_rule, _, previous) when previous == 0, do: :ok

  defp check_increase_regression(alert_rule, current, previous) do
    change_pct = (current - previous) / previous * 100

    if change_pct >= alert_rule.threshold_percentage do
      result = %{current: current, previous: previous, change_pct: Float.round(change_pct, 1)}
      {:triggered, Alert.from_rule(alert_rule, result)}
    else
      :ok
    end
  end

  defp check_decrease_regression(_alert_rule, nil, _), do: :ok
  defp check_decrease_regression(_alert_rule, _, nil), do: :ok
  defp check_decrease_regression(_alert_rule, _, previous) when previous == 0, do: :ok

  defp check_decrease_regression(alert_rule, current, previous) do
    change_pct = (previous - current) / previous * 100

    if change_pct >= alert_rule.threshold_percentage do
      result = %{current: current, previous: previous, change_pct: Float.round(change_pct, 1)}
      {:triggered, Alert.from_rule(alert_rule, result)}
    else
      :ok
    end
  end
end
