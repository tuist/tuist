defmodule Tuist.OnceEvents.CacheAnalyticsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query

  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Action
  alias Tuist.OnceEvents.CacheAnalytics
  alias Tuist.OnceEvents.CacheEvent
  alias Tuist.OnceEvents.Run
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    project = ProjectsFixtures.project_fixture()
    started_at = DateTime.add(DateTime.utc_now(), -3600, :second)

    ci_run = run(project, started_at, true)
    action(ci_run, "a", 0, true, 10)
    action(ci_run, "a", 1, true, 15)
    action(ci_run, "b", 0, false, 100)
    action(ci_run, "b", 1, false, 51)
    # A synthetic phase span is not a cache probe and must not count anywhere.
    OnceEvents.ingest_action(ci_run, action_attrs("a", 0, false, 999, "_phase"))
    cache_event(ci_run, "download", 1, bytes_transferred: 1000, duration_ms: 7)
    cache_event(ci_run, "upload", 2, bytes_transferred: 500, duration_ms: 3)
    cache_event(ci_run, "reused", 3, content_size_bytes: 2000)

    local_run = run(project, started_at, false)
    action(local_run, "c", 0, false, 20)
    action(local_run, "c", 1, true, 1)
    cache_event(local_run, "download", 4, bytes_transferred: 300, duration_ms: 5)

    %{project: project, ci_run: ci_run, local_run: local_run}
  end

  describe "summary/2" do
    test "matches the averages and totals over the individual actions and transfers", %{project: project} do
      # Cached: 10 + 15 + 1 = 26 over 3. Executed: 100 + 51 + 20 = 171 over 3.
      assert %{
               read_latency_ms: 9,
               write_latency_ms: 57,
               latency_ms: 33,
               download_bytes: 1300,
               upload_bytes: 500,
               transfer_bytes: 1800,
               download_throughput_bytes_per_second: 50_000,
               upload_throughput_bytes_per_second: 2923,
               throughput_bytes_per_second: 9137
             } = CacheAnalytics.summary(project.id)

      assert CacheAnalytics.summary(project.id) == row_level_summary(project.id, [])
    end

    test "the environment narrows the transfers, as it did before", %{project: project} do
      summary = CacheAnalytics.summary(project.id, is_ci: true)

      assert %{download_bytes: 1000, upload_bytes: 500, read_latency_ms: 9, write_latency_ms: 57} = summary
      assert summary == row_level_summary(project.id, is_ci: true)
    end

    test "is all zeros for a project without runs" do
      other = ProjectsFixtures.project_fixture()

      assert %{transfer_bytes: 0, latency_ms: 0, read_latency_ms: 0, throughput_bytes_per_second: 0} =
               CacheAnalytics.summary(other.id)
    end
  end

  describe "analytics/2" do
    test "buckets the same lookups, hits, latencies and observations", %{project: project} do
      analytics = CacheAnalytics.analytics(project.id)

      assert Enum.sum(analytics.lookup_values) == 6
      assert Enum.sum(analytics.observation_values) == 4
      assert Enum.max(analytics.hit_rate_values) == 50.0
      assert Enum.max(analytics.latency_values) == 33
      assert Enum.max(analytics.read_latency_values) == 9
      assert Enum.max(analytics.write_latency_values) == 57
      assert Enum.sum(analytics.download_bytes_values) == 1300
      assert Enum.sum(analytics.upload_bytes_values) == 500
    end

    test "the environment narrows the lookups but not the transfers, as it did before", %{project: project} do
      analytics = CacheAnalytics.analytics(project.id, is_ci: true)

      # Cached 25 over 2 and executed 151 over 2 round half up.
      assert Enum.sum(analytics.lookup_values) == 4
      assert Enum.sum(analytics.observation_values) == 4
      assert Enum.max(analytics.read_latency_values) == 13
      assert Enum.max(analytics.write_latency_values) == 76
    end
  end

  describe "run roll-ups" do
    test "equal the sums over the run's own rows, and replays do not inflate them", %{ci_run: ci_run} do
      action(ci_run, "a", 0, true, 10)
      cache_event(ci_run, "download", 1, bytes_transferred: 1000, duration_ms: 7)

      assert %{cached_action_ms_total: 25, executed_action_ms_total: 151, cache_event_count: 3} =
               reload(ci_run)

      assert ci_run |> reload() |> Map.take(rollup_fields()) == row_sums(ci_run)
    end

    test "a run finalizing recounts them from its rows", %{local_run: local_run} do
      # A run that was already streaming when the roll-ups were introduced has
      # some events projected without them.
      Repo.update_all(from(r in Run, where: r.id == ^local_run.id),
        set: [cached_action_ms_total: 0, executed_action_ms_total: 0, cache_event_count: 0]
      )

      {:ok, finalized} = OnceEvents.finalize_run(reload(local_run), %{finalization: "finalized", exit_status: 0})

      assert %{cached_action_ms_total: 1, executed_action_ms_total: 20, cache_event_count: 1} = finalized
      assert local_run |> reload() |> Map.take(rollup_fields()) == row_sums(local_run)
    end

    test "the sweep recounts runs that finished recently, such as ones an older pod finalized", %{
      ci_run: ci_run,
      local_run: local_run
    } do
      zeroed = [cached_action_ms_total: 0, executed_action_ms_total: 0, cache_event_count: 0]
      long_ago = DateTime.add(DateTime.utc_now(), -2 * 86_400, :second)

      # Finalized without the recount, the way the previous release does.
      Repo.update_all(from(r in Run, where: r.id == ^ci_run.id),
        set: zeroed ++ [finalization: "finalized", finalized_at: DateTime.utc_now()]
      )

      Repo.update_all(from(r in Run, where: r.id == ^local_run.id),
        set: zeroed ++ [finalization: "finalized", finalized_at: long_ago]
      )

      assert {:ok, 1} = OnceEvents.recount_recent_cache_rollups()

      assert ci_run |> reload() |> Map.take(rollup_fields()) == row_sums(ci_run)
      assert %{cached_action_ms_total: 0, cache_event_count: 0} = reload(local_run)
    end
  end

  defp run(project, started_at, is_ci) do
    {:ok, run} =
      OnceEvents.upsert_run(%{
        project_id: project.id,
        run_id: UUIDv7.generate(),
        kind: "build",
        is_ci: is_ci,
        started_at: started_at
      })

    run
  end

  defp action(run, target, index, cached, duration_ms) do
    {:ok, _} = OnceEvents.ingest_action(run, action_attrs(target, index, cached, duration_ms, "build"))
  end

  defp action_attrs(target, index, cached, duration_ms, capability) do
    %{
      target_execution_id: target,
      capability: capability,
      action_index: index,
      identifier: "#{target}-#{index}",
      result: "succeeded",
      was_cached: cached,
      duration_ms: duration_ms,
      exit_code: 0,
      finished_at: DateTime.utc_now()
    }
  end

  defp cache_event(run, kind, second, attrs) do
    :ok =
      OnceEvents.ingest_cache_event(
        run,
        Map.merge(
          %{
            kind: kind,
            target_execution_id: "a",
            content_hash: "hash-#{second}",
            observed_at: DateTime.from_unix!((1_700_000_000 + second) * 1_000_000, :microsecond)
          },
          Map.new(attrs)
        )
      )
  end

  defp reload(run), do: OnceEvents.get_run(run.project_id, run.run_id)

  defp rollup_fields, do: [:cached_action_ms_total, :executed_action_ms_total, :cache_event_count]

  defp row_sums(run) do
    ms = fn cached ->
      Repo.one(
        from(a in Action,
          where: a.once_run_id == ^run.id and a.was_cached == ^cached and a.capability != "_phase",
          select: coalesce(sum(a.duration_ms), 0)
        )
      )
    end

    %{
      cached_action_ms_total: Decimal.to_integer(Decimal.new(ms.(true))),
      executed_action_ms_total: Decimal.to_integer(Decimal.new(ms.(false))),
      cache_event_count: Repo.aggregate(from(e in CacheEvent, where: e.once_run_id == ^run.id), :count)
    }
  end

  # The row-level queries `summary/2` ran before it read the run roll-ups,
  # kept here as the reference the new implementation must agree with.
  defp row_level_summary(project_id, opts) do
    end_dt = DateTime.utc_now()
    start_dt = DateTime.add(end_dt, -30 * 86_400, :second)

    action_stats =
      Action
      |> where([a], a.project_id == ^project_id and a.capability != "_phase")
      |> join(:inner, [a], r in Run, on: r.id == a.once_run_id)
      |> where([_, r], r.started_at >= ^start_dt and r.started_at < ^end_dt)
      |> select([a, _], %{
        read_ms: fragment("coalesce(avg(case when ? then ? end), 0)", a.was_cached, a.duration_ms),
        write_ms: fragment("coalesce(avg(case when not ? then ? end), 0)", a.was_cached, a.duration_ms),
        avg_ms: fragment("coalesce(avg(?), 0)", a.duration_ms),
        read_ms_total: fragment("coalesce(sum(case when ? then ? end), 0)", a.was_cached, a.duration_ms),
        write_ms_total: fragment("coalesce(sum(case when not ? then ? end), 0)", a.was_cached, a.duration_ms)
      })
      |> Repo.one()

    transfers =
      CacheEvent
      |> where([e], e.project_id == ^project_id)
      |> join(:inner, [e], r in Run, on: r.id == e.once_run_id)
      |> where([_, r], r.started_at >= ^start_dt and r.started_at < ^end_dt)
      |> then(fn query ->
        case Keyword.get(opts, :is_ci) do
          nil -> query
          is_ci -> where(query, [_, r], r.is_ci == ^is_ci)
        end
      end)
      |> select([e, _], %{
        download_bytes: fragment("coalesce(sum(case when ? = 'download' then ? end), 0)", e.kind, e.bytes_transferred),
        upload_bytes: fragment("coalesce(sum(case when ? = 'upload' then ? end), 0)", e.kind, e.bytes_transferred)
      })
      |> Repo.one()

    int = fn value -> value |> Decimal.new() |> Decimal.round(0) |> Decimal.to_integer() end
    throughput = fn bytes, ms -> if ms > 0, do: div(bytes * 1000, ms), else: 0 end

    download = int.(transfers.download_bytes)
    upload = int.(transfers.upload_bytes)
    read_total = int.(action_stats.read_ms_total)
    write_total = int.(action_stats.write_ms_total)

    %{
      transfer_bytes: download + upload,
      download_bytes: download,
      upload_bytes: upload,
      latency_ms: int.(action_stats.avg_ms),
      read_latency_ms: int.(action_stats.read_ms),
      write_latency_ms: int.(action_stats.write_ms),
      throughput_bytes_per_second: throughput.(download + upload, read_total + write_total),
      download_throughput_bytes_per_second: throughput.(download, read_total),
      upload_throughput_bytes_per_second: throughput.(upload, write_total)
    }
  end
end
