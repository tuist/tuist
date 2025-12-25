defmodule Tuist.Slack.Reports do
  @moduledoc """
  Generates analytics reports for Slack notifications.
  """

  alias Tuist.Bundles
  alias Tuist.CommandEvents

  def generate_report(project, frequency, opts \\ []) do
    last_report_at = Keyword.get(opts, :last_report_at)
    {current_start, current_end, previous_start, previous_end} = compute_date_ranges(frequency, last_report_at)

    %{
      account_name: project.account.name,
      project_name: project.name,
      frequency: frequency,
      period: format_period(current_start, current_end),
      build_duration:
        compute_build_duration_metrics(project.id, current_start, current_end, previous_start, previous_end),
      test_duration: compute_test_duration_metrics(project.id, current_start, current_end, previous_start, previous_end),
      cache_hit_rate:
        compute_cache_hit_rate_metrics(project.id, current_start, current_end, previous_start, previous_end),
      selective_test_effectiveness:
        compute_selective_test_metrics(project.id, current_start, current_end, previous_start, previous_end),
      bundle_size: compute_bundle_size_metrics(project)
    }
  end

  def format_report_blocks(report) do
    metric_blocks =
      build_duration_blocks(report.build_duration) ++
        test_duration_blocks(report.test_duration) ++
        cache_hit_rate_blocks(report.cache_hit_rate) ++
        selective_test_blocks(report.selective_test_effectiveness) ++
        bundle_size_blocks(report.bundle_size)

    if Enum.empty?(metric_blocks) do
      [
        header_block(report),
        context_block(report),
        divider_block(),
        no_data_block(),
        footer_block(report.account_name, report.project_name)
      ]
    else
      [
        header_block(report),
        context_block(report),
        divider_block()
      ] ++ metric_blocks ++ [footer_block(report.account_name, report.project_name)]
    end
  end

  defp compute_date_ranges(_frequency, last_report_at) when not is_nil(last_report_at) do
    now = DateTime.utc_now()
    current_end = now
    current_start = last_report_at
    previous_end = current_start
    period_seconds = DateTime.diff(current_end, current_start, :second)
    previous_start = DateTime.add(previous_end, -period_seconds, :second)
    {current_start, current_end, previous_start, previous_end}
  end

  defp compute_date_ranges(:daily, _last_report_at) do
    now = DateTime.utc_now()
    current_end = now
    current_start = DateTime.add(now, -1, :day)
    previous_end = current_start
    previous_start = DateTime.add(previous_end, -1, :day)
    {current_start, current_end, previous_start, previous_end}
  end

  defp compute_date_ranges(:weekly, _last_report_at) do
    now = DateTime.utc_now()
    current_end = now
    current_start = DateTime.add(now, -7, :day)
    previous_end = current_start
    previous_start = DateTime.add(previous_end, -7, :day)
    {current_start, current_end, previous_start, previous_end}
  end

  defp compute_build_duration_metrics(project_id, current_start, current_end, previous_start, previous_end) do
    ci =
      compute_duration_change(project_id, current_start, current_end, previous_start, previous_end,
        is_ci: true,
        name: "build"
      )

    local =
      compute_duration_change(project_id, current_start, current_end, previous_start, previous_end,
        is_ci: false,
        name: "build"
      )

    overall =
      compute_duration_change(project_id, current_start, current_end, previous_start, previous_end, name: "build")

    %{ci: ci, local: local, overall: overall}
  end

  defp compute_test_duration_metrics(project_id, current_start, current_end, previous_start, previous_end) do
    ci =
      compute_duration_change(project_id, current_start, current_end, previous_start, previous_end,
        is_ci: true,
        name: "test"
      )

    local =
      compute_duration_change(project_id, current_start, current_end, previous_start, previous_end,
        is_ci: false,
        name: "test"
      )

    overall =
      compute_duration_change(project_id, current_start, current_end, previous_start, previous_end, name: "test")

    %{ci: ci, local: local, overall: overall}
  end

  defp compute_duration_change(project_id, current_start, current_end, previous_start, previous_end, opts) do
    current = CommandEvents.run_average_duration(project_id, current_start, current_end, opts)
    previous = CommandEvents.run_average_duration(project_id, previous_start, previous_end, opts)

    %{
      current: current,
      previous: previous,
      change_pct: calculate_change_percentage(current, previous)
    }
  end

  defp compute_cache_hit_rate_metrics(project_id, current_start, current_end, previous_start, previous_end) do
    current_data = CommandEvents.cache_hit_rate(project_id, current_start, current_end, [])
    previous_data = CommandEvents.cache_hit_rate(project_id, previous_start, previous_end, [])

    current = calculate_hit_rate(current_data)
    previous = calculate_hit_rate(previous_data)

    %{
      current: current,
      previous: previous,
      change_pct: calculate_change_percentage(current, previous)
    }
  end

  defp compute_selective_test_metrics(project_id, current_start, current_end, previous_start, previous_end) do
    current_data = CommandEvents.selective_testing_hit_rate(project_id, current_start, current_end, [])
    previous_data = CommandEvents.selective_testing_hit_rate(project_id, previous_start, previous_end, [])

    current = calculate_selective_test_rate(current_data)
    previous = calculate_selective_test_rate(previous_data)

    %{
      current: current,
      previous: previous,
      change_pct: calculate_change_percentage(current, previous)
    }
  end

  defp calculate_hit_rate(nil), do: nil

  defp calculate_hit_rate(%{cacheable_targets_count: nil}), do: nil
  defp calculate_hit_rate(%{cacheable_targets_count: 0}), do: nil

  defp calculate_hit_rate(%{
         cacheable_targets_count: cacheable,
         local_cache_hits_count: local_hits,
         remote_cache_hits_count: remote_hits
       }) do
    total_hits = (local_hits || 0) + (remote_hits || 0)
    total_hits / cacheable
  end

  defp calculate_selective_test_rate(nil), do: nil
  defp calculate_selective_test_rate(%{test_targets_count: nil}), do: nil
  defp calculate_selective_test_rate(%{test_targets_count: 0}), do: nil

  defp calculate_selective_test_rate(%{
         test_targets_count: test_targets,
         local_test_hits_count: local_hits,
         remote_test_hits_count: remote_hits
       }) do
    total_hits = (local_hits || 0) + (remote_hits || 0)
    total_hits / test_targets
  end

  defp compute_bundle_size_metrics(project) do
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

  defp calculate_change_percentage(_current, previous) when previous == 0 or is_nil(previous), do: nil
  defp calculate_change_percentage(current, _previous) when is_nil(current), do: nil

  defp calculate_change_percentage(current, previous) do
    Float.round((current - previous) / previous * 100, 1)
  end

  defp format_period(start_dt, end_dt) do
    start_ts = DateTime.to_unix(start_dt)
    end_ts = DateTime.to_unix(end_dt)
    start_fallback = Calendar.strftime(start_dt, "%b %d, %H:%M")
    end_fallback = Calendar.strftime(end_dt, "%b %d, %H:%M")

    "<!date^#{start_ts}^{date_short} {time}|#{start_fallback}> - <!date^#{end_ts}^{date_short} {time}|#{end_fallback}>"
  end

  defp header_block(report) do
    frequency_label = if report.frequency == :daily, do: "Daily", else: "Weekly"

    %{
      type: "header",
      text: %{
        type: "plain_text",
        text: "#{frequency_label} #{report.project_name} Report"
      }
    }
  end

  defp context_block(report) do
    %{
      type: "context",
      elements: [
        %{type: "mrkdwn", text: report.period}
      ]
    }
  end

  defp divider_block do
    %{type: "divider"}
  end

  defp build_duration_blocks(%{ci: ci, local: local, overall: overall}) do
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
            text: ":hammer_and_wrench: *Build Duration*\n" <> Enum.join(lines)
          }
        }
      ]
    end
  end

  defp test_duration_blocks(%{ci: ci, local: local, overall: overall}) do
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
            text: ":test_tube: *Test Duration*\n" <> Enum.join(lines)
          }
        }
      ]
    end
  end

  defp cache_hit_rate_blocks(%{current: nil}), do: []

  defp cache_hit_rate_blocks(%{current: current, change_pct: change_pct}) do
    change_text = format_change(change_pct, :higher_is_better)
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

  defp selective_test_blocks(%{current: nil}), do: []

  defp selective_test_blocks(%{current: current, change_pct: change_pct}) do
    change_text = format_change(change_pct, :higher_is_better)
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

  defp maybe_duration_line(_label, %{current: nil}), do: nil
  defp maybe_duration_line(_label, %{current: 0}), do: nil

  defp maybe_duration_line(label, %{current: current, change_pct: change_pct}) do
    duration_text = format_duration(current)
    change_text = format_change(change_pct, :lower_is_better)
    "#{label}: #{duration_text} #{change_text}\n"
  end

  defp format_duration(nil), do: "N/A"
  defp format_duration(0), do: "N/A"
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)}s"
  defp format_duration(ms), do: "#{Float.round(ms / 60_000, 1)}m"

  defp format_change(nil, _), do: ""

  defp format_change(change_pct, preference) do
    {icon, sign} =
      cond do
        change_pct > 0 and preference == :lower_is_better -> {":chart_with_upwards_trend:", "+"}
        change_pct > 0 and preference == :higher_is_better -> {":chart_with_upwards_trend:", "+"}
        change_pct < 0 and preference == :lower_is_better -> {":chart_with_downwards_trend:", ""}
        change_pct < 0 and preference == :higher_is_better -> {":chart_with_downwards_trend:", ""}
        true -> {"", ""}
      end

    if change_pct == 0 do
      ""
    else
      "(#{sign}#{change_pct}% #{icon})"
    end
  end
end
