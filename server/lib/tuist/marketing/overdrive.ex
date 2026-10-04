defmodule Tuist.Marketing.Overdrive do
  @moduledoc """
  Overdrive is the marketing directory of popular open source projects that
  Tuist forked and wired up to Tuist, to show how much faster they would move
  with it. The upstream maintainers are not involved: every entry names its
  upstream repository and the pages say plainly that the numbers come from
  Tuist's fork. Each entry must point to a Tuist project whose dashboard is
  public; a missing or private project is left out of the directory.

  Stats are the last 30 days of the fork's dashboard data, reduced to a few
  headline numbers that read the same across build systems. They are cached
  for an hour because the pages and their Open Graph cards are public and
  cacheable, and the numbers only need to be roughly current.
  """

  alias Tuist.Bazel
  alias Tuist.Builds.Analytics, as: BuildsAnalytics
  alias Tuist.Gradle.Analytics, as: GradleAnalytics
  alias Tuist.KeyValueStore
  alias Tuist.OnceEvents.Analytics, as: OnceAnalytics
  alias Tuist.OnceEvents.CacheAnalytics, as: OnceCacheAnalytics
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.ReapiCache
  alias Tuist.Tests.Analytics, as: TestsAnalytics

  @period_days 30
  @stats_ttl to_timeout(hour: 1)

  # Curated, in display order. `handle` is the fork's Tuist project full
  # handle, which is also the path under /overdrive.
  @entries [
    %{
      handle: "tuist/mise",
      name: "mise",
      description: "The front-end to your dev env: dev tools, environment variables, and tasks in one place.",
      upstream_handle: "jdx/mise",
      upstream_url: "https://github.com/jdx/mise",
      fork_url: "https://github.com/tuist/mise"
    }
  ]

  def period_days, do: @period_days

  def entries, do: @entries

  def get_entry(handle), do: Enum.find(@entries, &(&1.handle == handle))

  @doc """
  The directory's projects that are public in Tuist, with their stats.
  """
  def list_projects do
    @entries
    |> Enum.map(&load/1)
    |> Enum.flat_map(fn
      {:ok, project} -> [project]
      {:error, :not_found} -> []
    end)
  end

  def get_project(account_handle, project_handle) do
    handle = "#{account_handle}/#{project_handle}"

    case get_entry(handle) do
      nil -> {:error, :not_found}
      entry -> load(entry)
    end
  end

  defp load(%{handle: handle} = entry) do
    [account_handle, project_handle] = String.split(handle, "/")

    case Projects.get_project_by_account_and_project_handles(account_handle, project_handle) do
      %Project{visibility: :public} = project ->
        {:ok,
         Map.merge(entry, %{
           account_handle: account_handle,
           project_handle: project_handle,
           build_system: project.build_system,
           stats: cached_stats(project)
         })}

      _ ->
        {:error, :not_found}
    end
  end

  defp cached_stats(%Project{id: id} = project) do
    KeyValueStore.get_or_update([__MODULE__, :stats, id], [ttl: @stats_ttl], fn -> stats(project) end)
  end

  @doc """
  Headline numbers for the last #{@period_days} days. A metric the project's
  build system doesn't report, or that has no data in the period, is `nil`.
  """
  def stats(%Project{} = project, now \\ DateTime.utc_now()) do
    end_datetime = DateTime.truncate(now, :second)
    start_datetime = DateTime.add(end_datetime, -@period_days, :day)
    opts = [start_datetime: start_datetime, end_datetime: end_datetime]

    project
    |> build_system_stats(opts)
    |> Map.new(fn {key, value} -> {key, presence(value)} end)
    |> Map.put(:computed_at, end_datetime)
  end

  defp build_system_stats(%Project{build_system: :once, id: id}, opts) do
    builds = OnceAnalytics.summary(id, Keyword.put(opts, :commands, ["build"]))
    tests = OnceAnalytics.summary(id, Keyword.put(opts, :commands, ["test"]))
    cache = OnceCacheAnalytics.invocation_hit_rate_metrics(id, opts)

    %{
      builds: builds.total,
      median_build_duration_ms: builds.median_duration_ms,
      test_runs: tests.total,
      cache_hit_rate: if(cache.sample_count > 0, do: cache.avg)
    }
  end

  defp build_system_stats(%Project{build_system: :bazel, id: id}, opts) do
    builds = Bazel.summary(id, Keyword.put(opts, :commands, ["build"]))
    tests = Bazel.summary(id, Keyword.put(opts, :commands, ["test"]))
    cache = ReapiCache.invocation_hit_rate_metrics(id, opts)

    %{
      builds: builds.total,
      median_build_duration_ms: builds.median_duration_ms,
      test_runs: tests.total,
      cache_hit_rate: if(cache.sample_count > 0, do: cache.avg)
    }
  end

  defp build_system_stats(%Project{build_system: :gradle, id: id}, opts) do
    %{
      builds: GradleAnalytics.build_analytics(id, opts).count,
      median_build_duration_ms: nil,
      test_runs: nil,
      cache_hit_rate: GradleAnalytics.cache_hit_rate(id, opts[:start_datetime], opts[:end_datetime])
    }
  end

  defp build_system_stats(%Project{build_system: :xcode, id: id}, opts) do
    %{
      builds: BuildsAnalytics.build_analytics(id, opts).count,
      median_build_duration_ms: nil,
      test_runs: TestsAnalytics.test_run_analytics(id, opts).count,
      cache_hit_rate: BuildsAnalytics.build_cache_hit_rate_analytics(id, opts).avg_hit_rate
    }
  end

  @doc """
  The Open Graph card variables for a loaded project: its handle and its
  formatted headline numbers. Every value is part of the image's cache key,
  so the card is re-rendered when a number it shows changes.
  """
  def og_image_variables(%{handle: handle, stats: stats}) do
    [
      handle: handle,
      builds: format_count(stats.builds),
      cache_hit_rate: format_percentage(stats.cache_hit_rate),
      test_runs: format_count(stats.test_runs)
    ]
  end

  def format_count(nil), do: nil
  def format_count(count) when count >= 1_000_000, do: compact(count / 1_000_000, "M")
  def format_count(count) when count >= 1_000, do: compact(count / 1_000, "K")
  def format_count(count), do: count |> round() |> Integer.to_string()

  def format_percentage(nil), do: nil
  def format_percentage(value), do: "#{value |> min(100) |> round()}%"

  def format_duration(nil), do: nil

  def format_duration(ms) do
    seconds = round(ms / 1000)

    cond do
      seconds < 60 -> "#{max(seconds, 1)}s"
      seconds < 3600 -> "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
      true -> "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
    end
  end

  defp compact(value, suffix) do
    rounded = Float.round(value * 1.0, 1)
    if rounded == trunc(rounded), do: "#{trunc(rounded)}#{suffix}", else: "#{rounded}#{suffix}"
  end

  # Zero reads as "no data" on a showcase: a dash is more honest than a
  # 0% hit rate for a project that simply didn't run anything cacheable.
  defp presence(value) when is_number(value) and value > 0, do: value
  defp presence(_value), do: nil
end
