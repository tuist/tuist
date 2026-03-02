defmodule Tuist.Alerts do
  @moduledoc """
  Context module for managing alerts and alert rules.
  """
  import Ecto.Query

  alias Tuist.Alerts.Alert
  alias Tuist.Alerts.AlertRule
  alias Tuist.Builds.Analytics, as: BuildsAnalytics
  alias Tuist.Bundles
  alias Tuist.Bundles.Bundle
  alias Tuist.Cache.Analytics, as: CacheAnalytics
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Tests.Analytics, as: TestsAnalytics

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
    opts =
      [limit: alert_rule.rolling_window_size, offset: 0]
      |> maybe_add_scheme(alert_rule.scheme)
      |> maybe_add_environment(alert_rule.environment)

    current = BuildsAnalytics.build_duration_metric_by_count(alert_rule.project_id, alert_rule.metric, opts)

    previous_opts =
      [limit: alert_rule.rolling_window_size, offset: alert_rule.rolling_window_size]
      |> maybe_add_scheme(alert_rule.scheme)
      |> maybe_add_environment(alert_rule.environment)

    previous = BuildsAnalytics.build_duration_metric_by_count(alert_rule.project_id, alert_rule.metric, previous_opts)

    check_increase_regression(alert_rule, current, previous)
  end

  def evaluate(%AlertRule{category: :test_run_duration} = alert_rule) do
    opts =
      [limit: alert_rule.rolling_window_size, offset: 0]
      |> maybe_add_scheme(alert_rule.scheme)
      |> maybe_add_environment(alert_rule.environment)

    current = TestsAnalytics.test_duration_metric_by_count(alert_rule.project_id, alert_rule.metric, opts)

    previous_opts =
      [limit: alert_rule.rolling_window_size, offset: alert_rule.rolling_window_size]
      |> maybe_add_scheme(alert_rule.scheme)
      |> maybe_add_environment(alert_rule.environment)

    previous = TestsAnalytics.test_duration_metric_by_count(alert_rule.project_id, alert_rule.metric, previous_opts)

    check_increase_regression(alert_rule, current, previous)
  end

  def evaluate(%AlertRule{category: :bundle_size} = alert_rule) do
    project = %Project{id: alert_rule.project_id}

    bundle_opts = maybe_add_bundle_name([git_branch: alert_rule.git_branch, fallback: false], alert_rule.bundle_name)

    with %Bundle{} = current_bundle <- Bundles.last_project_bundle(project, bundle_opts),
         %Bundle{} = previous_bundle <-
           Bundles.last_project_bundle(project, Keyword.put(bundle_opts, :bundle, current_bundle)) do
      size_field = bundle_size_field(alert_rule.metric)
      current_size = Map.get(current_bundle, size_field)
      previous_size = Map.get(previous_bundle, size_field)

      check_increase_regression(alert_rule, current_size, previous_size)
    else
      nil -> :ok
    end
  end

  def evaluate(%AlertRule{category: :cache_hit_rate} = alert_rule) do
    current_opts = maybe_add_environment([limit: alert_rule.rolling_window_size, offset: 0], alert_rule.environment)

    current = CacheAnalytics.cache_hit_rate_metric_by_count(alert_rule.project_id, alert_rule.metric, current_opts)

    previous_opts =
      maybe_add_environment(
        [limit: alert_rule.rolling_window_size, offset: alert_rule.rolling_window_size],
        alert_rule.environment
      )

    previous = CacheAnalytics.cache_hit_rate_metric_by_count(alert_rule.project_id, alert_rule.metric, previous_opts)

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

  defp bundle_size_field(:install_size), do: :install_size
  defp bundle_size_field(:download_size), do: :download_size

  defp maybe_add_scheme(opts, ""), do: opts
  defp maybe_add_scheme(opts, scheme), do: Keyword.put(opts, :scheme, scheme)

  defp maybe_add_environment(opts, :ci), do: Keyword.put(opts, :is_ci, true)
  defp maybe_add_environment(opts, :local), do: Keyword.put(opts, :is_ci, false)
  defp maybe_add_environment(opts, _), do: opts

  defp maybe_add_bundle_name(opts, ""), do: opts
  defp maybe_add_bundle_name(opts, bundle_name), do: Keyword.put(opts, :name, bundle_name)

  defp get_latest_alert(alert_rule_id) do
    Alert
    |> where([a], a.alert_rule_id == ^alert_rule_id)
    |> order_by([a], desc: a.inserted_at)
    |> limit(1)
    |> Repo.one()
  end
end
