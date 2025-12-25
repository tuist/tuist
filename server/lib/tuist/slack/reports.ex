defmodule Tuist.Slack.Reports do
  @moduledoc """
  Generates analytics reports for Slack notifications.
  """

  alias Tuist.Bundles
  alias Tuist.Cache
  alias Tuist.Runs.Analytics
  alias Tuist.Utilities.DateFormatter

  def report(project, opts \\ []) do
    last_report_at = Keyword.get(opts, :last_report_at)
    {current_start, current_end} = get_date_range(last_report_at)

    base_opts = [project_id: project.id, start_datetime: current_start, end_datetime: current_end]
    ci_opts = Keyword.put(base_opts, :is_ci, true)
    local_opts = Keyword.put(base_opts, :is_ci, false)

    cache_analytics = Cache.Analytics.cache_hit_rate_analytics(base_opts)
    selective_analytics = Analytics.selective_testing_analytics(base_opts)

    build_duration = %{
      ci: Analytics.build_duration_analytics(project.id, ci_opts),
      local: Analytics.build_duration_analytics(project.id, local_opts),
      overall: Analytics.build_duration_analytics(project.id, base_opts)
    }

    test_duration = %{
      ci: Analytics.test_run_duration_analytics(project.id, ci_opts),
      local: Analytics.test_run_duration_analytics(project.id, local_opts),
      overall: Analytics.test_run_duration_analytics(project.id, base_opts)
    }

    cache_hit_rate = %{current: cache_analytics.cache_hit_rate, trend: cache_analytics.trend}
    selective_test_effectiveness = %{current: selective_analytics.hit_rate, trend: selective_analytics.trend}
    bundle_size = get_bundle_size_metrics(project)

    metric_blocks =
      duration_blocks(build_duration, ":hammer_and_wrench:", "Build Duration") ++
        duration_blocks(test_duration, ":test_tube:", "Test Duration") ++
        cache_hit_rate_blocks(cache_hit_rate) ++
        selective_test_blocks(selective_test_effectiveness) ++
        bundle_size_blocks(bundle_size)

    account_name = project.account.name
    project_name = project.name
    period = format_period(current_start, current_end)

    if Enum.empty?(metric_blocks) do
      [
        header_block(project_name),
        context_block(period),
        divider_block(),
        no_data_block(),
        footer_block(account_name, project_name)
      ]
    else
      [
        header_block(project_name),
        context_block(period),
        divider_block()
      ] ++ metric_blocks ++ [footer_block(account_name, project_name)]
    end
  end

  defp get_date_range(last_report_at) when not is_nil(last_report_at) do
    {last_report_at, DateTime.utc_now()}
  end

  defp get_date_range(_last_report_at) do
    now = DateTime.utc_now()
    {DateTime.add(now, -1, :day), now}
  end

  defp get_bundle_size_metrics(project) do
    latest_bundle = Bundles.last_project_bundle(project, git_branch: project.default_branch)

    if latest_bundle do
      deviation = Bundles.install_size_deviation(latest_bundle)
      previous_bundle = Bundles.last_project_bundle(project, git_branch: project.default_branch, bundle: latest_bundle)
      previous_size = if previous_bundle, do: previous_bundle.install_size, else: latest_bundle.install_size

      %{
        current_size: latest_bundle.install_size,
        difference: latest_bundle.install_size - previous_size,
        comparison_branch: project.default_branch,
        deviation_pct: deviation * 100
      }
    end
  end

  defp format_period(start_dt, end_dt) do
    start_ts = DateTime.to_unix(start_dt)
    end_ts = DateTime.to_unix(end_dt)
    start_fallback = Calendar.strftime(start_dt, "%b %d, %H:%M")
    end_fallback = Calendar.strftime(end_dt, "%b %d, %H:%M")

    "<!date^#{start_ts}^{date_short} {time}|#{start_fallback}> - <!date^#{end_ts}^{date_short} {time}|#{end_fallback}>"
  end

  defp header_block(project_name) do
    %{
      type: "header",
      text: %{
        type: "plain_text",
        text: "Daily #{project_name} Report"
      }
    }
  end

  defp context_block(period) do
    %{
      type: "context",
      elements: [
        %{type: "mrkdwn", text: period}
      ]
    }
  end

  defp divider_block do
    %{type: "divider"}
  end

  defp duration_blocks(%{ci: ci, local: local, overall: overall}, emoji, title) do
    lines =
      Enum.reject(
        [maybe_duration_line("Overall", overall), maybe_duration_line("CI", ci), maybe_duration_line("Local", local)],
        &is_nil/1
      )

    if Enum.empty?(lines) do
      []
    else
      [
        %{
          type: "section",
          text: %{
            type: "mrkdwn",
            text: "#{emoji} *#{title}*\n" <> Enum.join(lines)
          }
        }
      ]
    end
  end

  defp cache_hit_rate_blocks(%{current: current, trend: trend}) when current > 0 do
    change_text = format_change(trend)
    rate_text = "#{Float.round(current * 100, 1)}%"

    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: ":zap: *Cache Hit Rate*\n#{rate_text} #{change_text}"
        }
      }
    ]
  end

  defp cache_hit_rate_blocks(_), do: []

  defp selective_test_blocks(%{current: current, trend: trend}) when current > 0 do
    change_text = format_change(trend)
    rate_text = "#{Float.round(current * 100, 1)}%"

    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text: ":dart: *Selective Test Effectiveness*\n#{rate_text} #{change_text}"
        }
      }
    ]
  end

  defp selective_test_blocks(_), do: []

  defp bundle_size_blocks(nil), do: []

  defp bundle_size_blocks(deviation) do
    size_mb = Float.round(deviation.current_size / 1_000_000, 2)
    diff_mb = Float.round(deviation.difference / 1_000_000, 2)
    direction = if deviation.difference >= 0, do: "+", else: ""

    trend_icon =
      cond do
        deviation.difference > 0 -> " :chart_with_upwards_trend:"
        deviation.difference < 0 -> " :chart_with_downwards_trend:"
        true -> ""
      end

    [
      %{
        type: "section",
        text: %{
          type: "mrkdwn",
          text:
            ":package: *Bundle Size*\n#{size_mb} MB (#{direction}#{diff_mb} MB vs #{deviation.comparison_branch})#{trend_icon}"
        }
      }
    ]
  end

  defp footer_block(account_name, project_name) do
    base_url = Tuist.Environment.app_url()

    %{
      type: "context",
      elements: [
        %{
          type: "mrkdwn",
          text: "<#{base_url}/#{account_name}/#{project_name}|View analytics>"
        }
      ]
    }
  end

  defp no_data_block do
    %{
      type: "section",
      text: %{
        type: "mrkdwn",
        text: "No analytics data available for this period."
      }
    }
  end

  defp maybe_duration_line(_label, %{total_average_duration: nil}), do: nil
  defp maybe_duration_line(_label, %{total_average_duration: 0}), do: nil

  defp maybe_duration_line(label, %{total_average_duration: duration, trend: trend}) do
    duration_text = DateFormatter.format_duration_from_milliseconds(duration)
    change_text = format_change(trend)
    "#{label}: #{duration_text} #{change_text}\n"
  end

  defp format_change(nil), do: ""

  defp format_change(change_pct) do
    cond do
      change_pct > 0 -> "(+#{change_pct}% :chart_with_upwards_trend:)"
      change_pct < 0 -> "(#{change_pct}% :chart_with_downwards_trend:)"
      true -> ""
    end
  end
end
