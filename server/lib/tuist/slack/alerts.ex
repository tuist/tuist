defmodule Tuist.Slack.Alerts do
  @moduledoc """
  Evaluates alert conditions and builds Slack notification blocks.

  Alerts are triggered when a metric regresses beyond a configured threshold.
  """

  import Ecto.Query

  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Runs.Build
  alias Tuist.Slack.Alert
  alias Tuist.Utilities.DateFormatter

  @doc """
  Evaluates an alert condition.

  Returns:
  - `{:triggered, result}` if threshold exceeded
  - `:ok` if no alert needed
  """
  def evaluate(%Alert{category: :build_run_duration} = alert) do
    project = alert.project
    sample_size = alert.sample_size
    metric = alert.metric

    current = get_build_metric(project.id, metric, limit: sample_size, offset: 0)
    previous = get_build_metric(project.id, metric, limit: sample_size, offset: sample_size)

    check_increase_regression(current, previous, alert.threshold_percentage)
  end

  def evaluate(%Alert{category: :test_run_duration} = alert) do
    project = alert.project
    sample_size = alert.sample_size
    metric = alert.metric

    current = get_test_metric(project.id, metric, limit: sample_size, offset: 0)
    previous = get_test_metric(project.id, metric, limit: sample_size, offset: sample_size)

    check_increase_regression(current, previous, alert.threshold_percentage)
  end

  def evaluate(%Alert{category: :cache_hit_rate} = alert) do
    project = alert.project
    sample_size = alert.sample_size
    metric = alert.metric

    current = get_cache_hit_rate_metric(project.id, metric, limit: sample_size, offset: 0)
    previous = get_cache_hit_rate_metric(project.id, metric, limit: sample_size, offset: sample_size)

    check_decrease_regression(current, previous, alert.threshold_percentage)
  end

  defp check_increase_regression(nil, _, _), do: :ok
  defp check_increase_regression(_, nil, _), do: :ok
  defp check_increase_regression(_, previous, _) when previous == 0, do: :ok

  defp check_increase_regression(current, previous, threshold) do
    change_pct = (current - previous) / previous * 100

    if change_pct >= threshold do
      {:triggered,
       %{
         current: current,
         previous: previous,
         change_pct: Float.round(change_pct, 1)
       }}
    else
      :ok
    end
  end

  defp check_decrease_regression(nil, _, _), do: :ok
  defp check_decrease_regression(_, nil, _), do: :ok
  defp check_decrease_regression(_, previous, _) when previous == 0, do: :ok

  defp check_decrease_regression(current, previous, threshold) do
    change_pct = (previous - current) / previous * 100

    if change_pct >= threshold do
      {:triggered,
       %{
         current: current,
         previous: previous,
         change_pct: Float.round(change_pct, 1)
       }}
    else
      :ok
    end
  end

  defp get_build_metric(project_id, metric, opts) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    durations =
      Repo.all(
        from(b in Build,
          where: b.project_id == ^project_id,
          order_by: [desc: b.inserted_at],
          limit: ^limit,
          offset: ^offset,
          select: b.duration
        )
      )

    calculate_metric(durations, metric)
  end

  defp get_test_metric(project_id, metric, opts) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    query = """
    SELECT duration
    FROM test_runs
    WHERE project_id = {project_id:Int64}
    ORDER BY ran_at DESC
    LIMIT {limit:Int32}
    OFFSET {offset:Int32}
    """

    case Tuist.ClickHouseRepo.query(query, %{
           "project_id" => project_id,
           "limit" => limit,
           "offset" => offset
         }) do
      {:ok, %{rows: rows}} ->
        durations = Enum.map(rows, fn [duration] -> duration end)
        calculate_metric(durations, metric)

      {:error, _} ->
        nil
    end
  end

  defp get_cache_hit_rate_metric(project_id, metric, opts) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    hit_rates =
      Repo.all(
        from(b in Build,
          where: b.project_id == ^project_id and not is_nil(b.cacheable_tasks_count) and b.cacheable_tasks_count > 0,
          order_by: [desc: b.inserted_at],
          limit: ^limit,
          offset: ^offset,
          select:
            fragment(
              "(COALESCE(?, 0) + COALESCE(?, 0))::float / ?",
              b.cacheable_task_local_hits_count,
              b.cacheable_task_remote_hits_count,
              b.cacheable_tasks_count
            )
        )
      )

    calculate_metric(hit_rates, metric)
  end

  defp calculate_metric([], _metric), do: nil

  defp calculate_metric(values, :average) do
    Enum.sum(values) / length(values)
  end

  defp calculate_metric(values, percentile) do
    sorted = Enum.sort(values)
    count = length(sorted)

    index =
      case percentile do
        :p50 -> trunc(count * 0.5)
        :p90 -> trunc(count * 0.9)
        :p99 -> trunc(count * 0.99)
      end

    index = min(index, count - 1)
    Enum.at(sorted, index)
  end

  @doc """
  Builds Slack Block Kit blocks for an alert notification.
  """
  def build_alert_blocks(alert, result) do
    project = alert.project
    account_name = project.account.name
    project_name = project.name

    [
      header_block(alert),
      context_block(),
      divider_block(),
      metric_block(alert, result),
      footer_block(account_name, project_name)
    ]
  end

  defp header_block(alert) do
    emoji = category_emoji(alert.category)
    title = alert_title(alert)

    %{
      type: "header",
      text: %{
        type: "plain_text",
        text: "#{emoji} Alert: #{title}"
      }
    }
  end

  defp context_block do
    now = DateTime.utc_now()
    ts = DateTime.to_unix(now)
    fallback = Calendar.strftime(now, "%b %d, %H:%M")

    %{
      type: "context",
      elements: [
        %{type: "mrkdwn", text: "Triggered at <!date^#{ts}^{date_short} {time}|#{fallback}>"}
      ]
    }
  end

  defp divider_block, do: %{type: "divider"}

  defp metric_block(alert, result) do
    message = format_alert_message(alert, result)

    %{
      type: "section",
      text: %{
        type: "mrkdwn",
        text: message
      }
    }
  end

  defp footer_block(account_name, project_name) do
    base_url = Environment.app_url()

    %{
      type: "context",
      elements: [
        %{
          type: "mrkdwn",
          text: "<#{base_url}/#{account_name}/#{project_name}|View project>"
        }
      ]
    }
  end

  defp category_emoji(:build_run_duration), do: ":hammer_and_wrench:"
  defp category_emoji(:test_run_duration), do: ":test_tube:"
  defp category_emoji(:cache_hit_rate), do: ":zap:"

  defp alert_title(%Alert{category: :build_run_duration, metric: metric}) do
    "Build Time #{metric_label(metric)} Increased"
  end

  defp alert_title(%Alert{category: :test_run_duration, metric: metric}) do
    "Test Time #{metric_label(metric)} Increased"
  end

  defp alert_title(%Alert{category: :cache_hit_rate, metric: metric}) do
    "Cache Hit Rate #{metric_label(metric)} Decreased"
  end

  defp metric_label(:p50), do: "P50"
  defp metric_label(:p90), do: "P90"
  defp metric_label(:p99), do: "P99"
  defp metric_label(:average), do: "Average"
  defp metric_label(nil), do: ""

  defp format_alert_message(alert, result) do
    case alert.category do
      :build_run_duration ->
        "*Build time #{metric_label(alert.metric)} increased by #{result.change_pct}%*\n" <>
          "Previous: #{format_duration(result.previous)}\n" <>
          "Current: #{format_duration(result.current)}"

      :test_run_duration ->
        "*Test time #{metric_label(alert.metric)} increased by #{result.change_pct}%*\n" <>
          "Previous: #{format_duration(result.previous)}\n" <>
          "Current: #{format_duration(result.current)}"

      :cache_hit_rate ->
        "*Cache hit rate #{metric_label(alert.metric)} decreased by #{result.change_pct}%*\n" <>
          "Previous: #{format_percentage(result.previous)}\n" <>
          "Current: #{format_percentage(result.current)}"
    end
  end

  defp format_duration(ms) when is_number(ms) do
    DateFormatter.format_duration_from_milliseconds(ms)
  end

  defp format_percentage(rate) when is_number(rate) do
    "#{Float.round(rate * 100, 1)}%"
  end
end
