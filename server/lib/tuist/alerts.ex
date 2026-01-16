defmodule Tuist.Alerts do
  @moduledoc """
  Context module for managing alerts and alert rules.
  """
  import Ecto.Query

  alias Tuist.Alerts.Alert
  alias Tuist.Alerts.AlertRule
  alias Tuist.Alerts.FlakyTestAlert
  alias Tuist.Alerts.FlakyTestAlertRule
  alias Tuist.Cache.Analytics, as: CacheAnalytics
  alias Tuist.ClickHouseRepo
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Runs.Analytics
  alias Tuist.Runs.TestCaseRun

  def get_project_alert_rules(%Project{id: project_id}) do
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

  def get_all_alert_rules do
    AlertRule
    |> Repo.all()
    |> Repo.preload(project: [account: :slack_installation])
  end

  def create_alert(attrs) do
    %Alert{}
    |> Alert.changeset(attrs)
    |> Repo.insert()
  end

  def cooldown_elapsed?(%AlertRule{id: alert_rule_id}) do
    case get_latest_alert(alert_rule_id) do
      nil -> true
      alert -> DateTime.diff(DateTime.utc_now(), alert.inserted_at, :hour) >= 24
    end
  end

  @doc """
  Evaluates an alert rule and returns triggered data if deviation exceeded.

  Returns:
  - `{:triggered, %{current: number, previous: number, deviation: float}}` if threshold exceeded
  - `:ok` if no alert needed
  """
  def evaluate(%AlertRule{category: :build_run_duration} = alert_rule) do
    current =
      Analytics.build_duration_metric_by_count(alert_rule.project_id, alert_rule.metric,
        limit: alert_rule.rolling_window_size,
        offset: 0
      )

    previous =
      Analytics.build_duration_metric_by_count(alert_rule.project_id, alert_rule.metric,
        limit: alert_rule.rolling_window_size,
        offset: alert_rule.rolling_window_size
      )

    check_increase_regression(alert_rule, current, previous)
  end

  def evaluate(%AlertRule{category: :test_run_duration} = alert_rule) do
    current =
      Analytics.test_duration_metric_by_count(alert_rule.project_id, alert_rule.metric,
        limit: alert_rule.rolling_window_size,
        offset: 0
      )

    previous =
      Analytics.test_duration_metric_by_count(alert_rule.project_id, alert_rule.metric,
        limit: alert_rule.rolling_window_size,
        offset: alert_rule.rolling_window_size
      )

    check_increase_regression(alert_rule, current, previous)
  end

  def evaluate(%AlertRule{category: :cache_hit_rate} = alert_rule) do
    current =
      CacheAnalytics.cache_hit_rate_metric_by_count(alert_rule.project_id, alert_rule.metric,
        limit: alert_rule.rolling_window_size,
        offset: 0
      )

    previous =
      CacheAnalytics.cache_hit_rate_metric_by_count(alert_rule.project_id, alert_rule.metric,
        limit: alert_rule.rolling_window_size,
        offset: alert_rule.rolling_window_size
      )

    check_decrease_regression(alert_rule, current, previous)
  end

  defp check_increase_regression(_alert_rule, nil, _), do: :ok
  defp check_increase_regression(_alert_rule, _, nil), do: :ok
  defp check_increase_regression(_alert_rule, _, previous) when previous == 0, do: :ok

  defp check_increase_regression(alert_rule, current, previous) do
    deviation = (current - previous) / previous * 100

    if deviation >= alert_rule.deviation_percentage do
      {:triggered, %{current: current, previous: previous, deviation: Float.round(deviation, 1)}}
    else
      :ok
    end
  end

  defp check_decrease_regression(_alert_rule, nil, _), do: :ok
  defp check_decrease_regression(_alert_rule, _, nil), do: :ok
  defp check_decrease_regression(_alert_rule, _, previous) when previous == 0, do: :ok

  defp check_decrease_regression(alert_rule, current, previous) do
    deviation = (previous - current) / previous * 100

    if deviation >= alert_rule.deviation_percentage do
      {:triggered, %{current: current, previous: previous, deviation: Float.round(deviation, 1)}}
    else
      :ok
    end
  end

  defp get_latest_alert(alert_rule_id) do
    Alert
    |> where([a], a.alert_rule_id == ^alert_rule_id)
    |> order_by([a], desc: a.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  # Flaky Test Alert Rule functions

  def get_project_flaky_test_alert_rules(%Project{id: project_id}) do
    FlakyTestAlertRule
    |> where([a], a.project_id == ^project_id)
    |> order_by([a], asc: a.inserted_at)
    |> Repo.all()
  end

  def get_flaky_test_alert_rule(id) do
    case Repo.get(FlakyTestAlertRule, id) do
      nil -> {:error, :not_found}
      rule -> {:ok, rule}
    end
  end

  def create_flaky_test_alert_rule(attrs) do
    %FlakyTestAlertRule{}
    |> FlakyTestAlertRule.changeset(attrs)
    |> Repo.insert()
  end

  def update_flaky_test_alert_rule(%FlakyTestAlertRule{} = rule, attrs) do
    rule
    |> FlakyTestAlertRule.changeset(attrs)
    |> Repo.update()
  end

  def delete_flaky_test_alert_rule(%FlakyTestAlertRule{} = rule) do
    Repo.delete(rule)
  end

  def get_flaky_test_alert_rules_by_project_id(project_id) do
    FlakyTestAlertRule
    |> where([r], r.project_id == ^project_id)
    |> Repo.all()
  end

  def get_all_flaky_test_alert_rules do
    FlakyTestAlertRule
    |> Repo.all()
    |> Repo.preload(project: [account: :slack_installation])
  end

  def create_flaky_test_alert(attrs) do
    %FlakyTestAlert{}
    |> FlakyTestAlert.changeset(attrs)
    |> Repo.insert()
  end

  def flaky_test_cooldown_elapsed?(%FlakyTestAlertRule{id: rule_id}) do
    case get_latest_flaky_test_alert(rule_id) do
      nil -> true
      alert -> DateTime.diff(DateTime.utc_now(), alert.inserted_at, :hour) >= 24
    end
  end

  @doc """
  Evaluates a flaky test alert rule by counting flaky runs in the last 30 days.

  Returns:
  - `{:triggered, %{flaky_runs_count: integer}}` if threshold exceeded
  - `:ok` if no alert needed
  """
  def evaluate_flaky_test_alert(%FlakyTestAlertRule{} = rule) do
    thirty_days_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -30, :day)

    flaky_runs_count =
      ClickHouseRepo.one(
        from(tcr in TestCaseRun,
          hints: ["FINAL"],
          where: tcr.project_id == ^rule.project_id,
          where: tcr.is_flaky == true,
          where: tcr.inserted_at >= ^thirty_days_ago,
          select: count(tcr.id, :distinct)
        )
      )

    flaky_runs_count = flaky_runs_count || 0

    if flaky_runs_count >= rule.trigger_threshold do
      {:triggered, %{flaky_runs_count: flaky_runs_count}}
    else
      :ok
    end
  end

  defp get_latest_flaky_test_alert(rule_id) do
    FlakyTestAlert
    |> where([a], a.flaky_test_alert_rule_id == ^rule_id)
    |> order_by([a], desc: a.inserted_at)
    |> limit(1)
    |> Repo.one()
  end
end
