defmodule Tuist.Marketing.BazelShowcase do
  @moduledoc """
  Bazel analytics for the live dashboard and invocation timeline embedded in
  the Bazel announcement blog post.

  The post is public and its traffic is mostly anonymous, so results are
  cached briefly instead of querying ClickHouse on every visit, and only
  aggregates leave the dashboard path: no branches, commits, targets, or links
  into the project's dashboard. Production reads `tuist/kura`; development
  points `:marketing_bazel_showcase_project` at a seeded project.
  """

  alias Tuist.Bazel
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.ReapiCache

  @default_project "tuist/kura"
  @period_days 30
  @recent_invocations_limit 30
  @timeline_lookback_days 7
  @timeline_candidates 50
  @cache_ttl to_timeout(minute: 1)

  def project_handle do
    Application.get_env(:tuist, :marketing_bazel_showcase_project, @default_project)
  end

  def period_days, do: @period_days

  def get do
    cached([:marketing, :bazel_showcase, project_handle()], &load/1)
  end

  def load(full_handle) do
    case fetch_project(full_handle) do
      {:ok, project} -> {:ok, analytics(project, full_handle)}
      error -> error
    end
  end

  @doc """
  The recent invocation with the richest timeline, so the post shows as much
  of a real build as the project has retained.
  """
  def timeline_invocation do
    cached([:marketing, :bazel_showcase_timeline, project_handle()], &load_timeline_invocation/1)
  end

  def load_timeline_invocation(full_handle) do
    with {:ok, project} <- fetch_project(full_handle),
         %{} = invocation <- richest_timeline_invocation(project) do
      {:ok, %{project: project, invocation: invocation}}
    else
      _ -> {:error, :not_found}
    end
  end

  defp cached(key, loader) do
    full_handle = project_handle()

    if Environment.test?() do
      loader.(full_handle)
    else
      KeyValueStore.get_or_update(key, [ttl: @cache_ttl], fn -> loader.(full_handle) end)
    end
  end

  defp fetch_project(full_handle) do
    with [account_handle, project_handle] <- String.split(full_handle, "/", parts: 2),
         %Project{} = project <- Projects.get_project_by_account_and_project_handles(account_handle, project_handle) do
      {:ok, project}
    else
      _ -> {:error, :not_found}
    end
  end

  defp analytics(project, full_handle) do
    opts = period_opts(@period_days)

    summary = Bazel.summary(project.id, opts)
    cache_summary = ReapiCache.summary(project.id, opts)

    recent_invocations =
      project.id
      |> Bazel.recent_invocations(Keyword.put(opts, :limit, @recent_invocations_limit))
      |> Enum.map(&Map.take(&1, [:command, :status, :duration_ms, :finished_at]))

    %{
      project: full_handle,
      invocations: summary.total,
      success_rate: percentage(summary.successful, summary.total),
      median_duration_ms: summary.median_duration_ms,
      cache_hit_rate: cache_summary.hit_rate,
      recent_invocations: recent_invocations
    }
  end

  # Candidates arrive newest first, so the newest of equally rich timelines wins.
  defp richest_timeline_invocation(project) do
    project.id
    |> Bazel.recent_invocations(Keyword.put(period_opts(@timeline_lookback_days), :limit, @timeline_candidates))
    |> Enum.reject(&(&1.build_timeline_span_start_ms == []))
    |> Enum.max_by(&length(&1.build_timeline_span_start_ms), fn -> nil end)
  end

  defp period_opts(days) do
    end_datetime = DateTime.utc_now()
    [start_datetime: DateTime.add(end_datetime, -days * 86_400, :second), end_datetime: end_datetime]
  end

  defp percentage(_part, total) when total in [nil, 0], do: nil
  defp percentage(part, total), do: Float.round(part / total * 100, 1)
end
