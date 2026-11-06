defmodule Tuist.Cargo.CacheTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Cargo.Build
  alias Tuist.Cargo.Cache
  alias Tuist.Cargo.CacheMetrics
  alias Tuist.IngestRepo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :cargo)
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    opts = [start_datetime: NaiveDateTime.add(now, -3600), end_datetime: NaiveDateTime.add(now, 60)]
    %{user: user, project: project, now: now, opts: opts}
  end

  test "rates use per-build reuse decisions, deduplicate retries and compare the preceding period", context do
    id = insert(context, %{version: 1, hits: 6, misses: 1, unconsulted: 2, verifications: 1, prefetched_actions: 99})
    insert(context, %{version: 1, hits: 6, misses: 1, unconsulted: 2, verifications: 1, prefetched_actions: 99}, id: id)
    insert(context, %{version: 1, hits: 1}, is_ci: true)
    insert(%{context | now: NaiveDateTime.add(context.now, -4000)}, %{version: 1, hits: 1, misses: 1})
    insert(context, %{version: 1, prefetched_actions: 10})

    analytics = Cache.hit_rate_analytics(context.project.id, context.opts)
    assert analytics.metrics.avg == 80.0
    assert analytics.metrics.p99 == 100.0
    assert analytics.trends.avg == 60.0
    assert [%{avg: 80.0}] = analytics.series
    assert Cache.hit_rate_analytics(context.project.id, context.opts ++ [is_ci: false]).metrics.avg == 60.0
  end

  test "upload retries across the period boundary stay in their first-seen cohort", context do
    start_datetime = context.opts[:start_datetime]
    metrics = %{version: 1, hits: 1, downloaded_bytes: 100}
    id = insert(%{context | now: NaiveDateTime.add(start_datetime, -1)}, metrics)
    insert(%{context | now: NaiveDateTime.add(start_datetime, 1)}, metrics, id: id)
    current = insert(context, %{version: 1, misses: 1, downloaded_bytes: 200})

    rates = Cache.hit_rate_analytics(context.project.id, context.opts)
    assert rates.metrics.avg == 0.0
    assert rates.trends.avg == -100.0
    io = Cache.io_analytics(context.project.id, context.opts)
    assert io.transfer.metrics["combined"] == 200
    assert io.transfer.trends["combined"] == 100.0
    assert [%{build: %{id: ^current}}] = Cache.recent_builds(context.project.id, context.opts)

    assert %{series: [%{data: [%{id: ^current}]}]} = Cache.hit_rate_scatter_data(context.project.id, context.opts)
  end

  test "all dashboard reads share project, environment, half-open date and build-command scopes", context do
    mine = insert(context, %{version: 1, unconsulted: 1})
    other = ProjectsFixtures.project_fixture(account_id: context.user.account.id, build_system: :cargo)
    insert(%{context | project: other}, %{version: 1, hits: 1}, id: mine)
    insert(context, %{version: 1, hits: 1}, command: "nextest")
    insert(context, %{version: 1, hits: 1}, is_ci: true)
    insert(%{context | now: NaiveDateTime.add(context.now, -7200)}, %{version: 1, hits: 1})
    insert(%{context | now: context.opts[:end_datetime]}, %{version: 1, hits: 1})
    opts = context.opts ++ [is_ci: false]

    assert Cache.hit_rate_analytics(context.project.id, opts).metrics.avg == 0.0
    assert [%{build: %{id: ^mine}, cache: %{hit_rate: recent_rate}}] = Cache.recent_builds(context.project.id, opts)
    assert recent_rate == 0.0

    assert %{truncated: false, series: [%{name: false, data: [%{id: ^mine, value: [_, scatter_rate]}]}]} =
             Cache.hit_rate_scatter_data(context.project.id, opts)

    assert scatter_rate == 0.0

    assert Cache.io_analytics(context.project.id, opts).transfer.metrics["combined"] == nil
  end

  test "legacy and malformed metrics stay unavailable while recorded cold compilations are zero", context do
    for metrics <- [
          nil,
          "not-json",
          ~s({"version":2,"hits":10}),
          ~s({"version":"1","hits":10}),
          ~s({"version":1.0,"hits":10}),
          ~s({"version":1,"hits":-1}),
          ~s({"version":1,"hits":"1"})
        ] do
      insert(context, metrics)
    end

    assert %{metrics: %{avg: nil, p99: nil}, series: []} = Cache.hit_rate_analytics(context.project.id, context.opts)
    assert %{series: []} = Cache.hit_rate_scatter_data(context.project.id, context.opts)
    assert Enum.all?(Cache.recent_builds(context.project.id, context.opts), &is_nil(&1.cache.hit_rate))

    insert(context, %{version: 1, unconsulted: 10, verifications: 2})
    assert Cache.hit_rate_analytics(context.project.id, context.opts).metrics.avg == 0.0
  end

  test "every counter retains strict type and range validation after field extraction", context do
    for counter <- CacheMetrics.counters(),
        invalid <- [-1, 1.0, "1", nil, CacheMetrics.maximum() + 1, 18_446_744_073_709_551_615] do
      metrics = Map.put(%{version: 1, hits: 1}, counter, invalid)
      insert(context, JSON.encode!(metrics))
    end

    assert Cache.hit_rate_analytics(context.project.id, context.opts).metrics.avg == nil
    assert Cache.io_analytics(context.project.id, context.opts).transfer.metrics["combined"] == nil
    assert Enum.all?(Cache.recent_builds(context.project.id, context.opts), &(not &1.cache.available))

    insert(context, %{version: 1, hits: 1, prefetched_actions: CacheMetrics.maximum()})
    assert Cache.hit_rate_analytics(context.project.id, context.opts).metrics.avg == 100.0
  end

  test "noncanonical inspection JSON preserves strict aggregate validation", context do
    details = ~s({ "version": 1, "truncated": false, "tasks": [], "cas_outputs": [] })
    insert(context, ~s({"version":1,"hits":1,"details":#{details}}))
    insert(context, ~s({"version":1,"hits":1.0,"details":#{details}}))
    insert(context, ~s({"version":1,"hits":1.0,"details":{"number":1.0}}))
    insert(context, ~s({"version":1,"hits":1,"details":"not an inspection object"}))

    assert Cache.hit_rate_analytics(context.project.id, context.opts).metrics.avg == 100.0
    assert %{series: [%{data: points}]} = Cache.hit_rate_scatter_data(context.project.id, context.opts)
    assert length(points) == 2
  end

  test "large bounded inspection payloads preserve aggregate and operation measurements", context do
    key = "sha256:#{String.duplicate("a", 64)}:1000"
    task = %{key: key, name: "registry-leaf", kind: "rust", status: "hit", read_duration_ns: 10_000_000}
    output = %{key: key, operation: "download", status: "downloaded", size_bytes: 1000, duration_ns: 10_000_000}

    metrics = %{
      version: 1,
      hits: 1,
      downloaded_bytes: 5_000_000,
      details: %{
        version: 1,
        truncated: false,
        tasks: List.duplicate(task, 2000),
        cas_outputs: List.duplicate(output, 5000)
      }
    }

    {:ok, json} = CacheMetrics.encode(metrics)
    assert byte_size(json) > 1_000_000
    insert(context, json)
    assert Cache.hit_rate_analytics(context.project.id, context.opts).metrics.avg == 100.0
    io = Cache.io_analytics(context.project.id, context.opts)
    assert io.transfer.metrics["combined"] == 5_000_000
    assert io.latency.metrics["read"] == 10.0
    assert io.throughput.metrics["downloads"] == 100_000.0
  end

  test "transport uses aggregate bytes, per-key latency, and time-weighted successful CAS transfers", context do
    key = "sha256:#{String.duplicate("a", 64)}:1000"

    metrics = %{
      version: 1,
      hits: 1,
      downloaded_bytes: 3000,
      uploaded_bytes: 2000,
      remote_blob_transfer_duration_ns: 999_000_000,
      details: %{
        version: 1,
        truncated: true,
        tasks: [
          %{key: key, name: "a", kind: "rust", status: "hit", read_duration_ns: 10_000_000},
          %{key: key, name: "b", kind: "rust", status: "miss", write_duration_ns: 30_000_000}
        ],
        cas_outputs: [
          %{key: key, operation: "download", status: "downloaded", size_bytes: 1000, duration_ns: 10_000_000},
          %{key: key, operation: "download", status: "downloaded", size_bytes: 2000, duration_ns: 20_000_000},
          %{key: key, operation: "upload", status: "uploaded", size_bytes: 2000, duration_ns: 20_000_000},
          %{key: key, operation: "upload", status: "present", size_bytes: 9000, duration_ns: 10_000_000},
          %{key: key, operation: "download", status: "failed", size_bytes: 9000, duration_ns: 10_000_000},
          %{key: key, operation: "download", status: "downloaded", size_bytes: 9000, duration_ns: 0}
        ]
      }
    }

    id = insert(context, metrics)
    insert(context, metrics, id: id)
    insert(context, %{version: 1, hits: 1})
    insert(context, Map.put(metrics, :downloaded_bytes, 9999), is_ci: true)
    analytics = Cache.io_analytics(context.project.id, context.opts ++ [is_ci: false])
    assert analytics.transfer.metrics == %{"combined" => 5000, "downloads" => 3000, "uploads" => 2000}
    assert analytics.latency.metrics == %{"combined" => 20.0, "read" => 10.0, "write" => 30.0}
    assert analytics.throughput.metrics == %{"combined" => 100_000.0, "downloads" => 100_000.0, "uploads" => 100_000.0}
    assert [%{"combined" => 5000, date: _}] = analytics.transfer.series
  end

  test "unreported transfer values and zero-duration throughput remain unavailable", context do
    insert(context, %{version: 1, misses: 1})
    empty = Cache.io_analytics(context.project.id, context.opts)
    for metric <- [:transfer, :latency, :throughput], do: assert(empty[metric].metrics["combined"] == nil)
    insert(context, %{version: 1, downloaded_bytes: 0, uploaded_bytes: 0})
    measured = Cache.io_analytics(context.project.id, context.opts)
    assert measured.transfer.metrics["combined"] == 0
    assert measured.latency.metrics["combined"] == nil
    assert measured.throughput.metrics["combined"] == nil
  end

  test "recent builds are bounded, preload reporters, and keep unavailable rows", context do
    for index <- 1..55 do
      insert(%{context | now: NaiveDateTime.add(context.now, -index)}, if(index == 55, do: %{version: 1, hits: 1}))
    end

    rows = Cache.recent_builds(context.project.id, context.opts)
    assert length(rows) == 50
    assert Enum.all?(rows, &(&1.build.ran_by_account.id == context.user.account.id))
    assert Enum.all?(rows, &is_nil(&1.build.cache_metrics))
    assert Cache.recent_hit_rate(rows) == nil
    assert Cache.recent_hit_rate([%{cache: %{hit_rate: 0.0}}, %{cache: %{hit_rate: nil}}]) == 0.0
  end

  test "scatter marks truncation only when a point is actually omitted", context do
    rows =
      Enum.map(1..10_000, fn _ ->
        %{
          id: Ecto.UUID.generate(),
          project_id: context.project.id,
          account_id: context.user.account.id,
          command: "build",
          status: "success",
          duration_ms: 1,
          is_ci: false,
          cache_metrics: ~s({"version":1,"hits":1}),
          inserted_at: context.now
        }
      end)

    IngestRepo.insert_all(Build, rows)
    exact = Cache.hit_rate_scatter_data(context.project.id, context.opts)
    refute exact.truncated
    assert length(hd(exact.series).data) == 10_000
    insert(context, %{version: 1, hits: 1})
    truncated = Cache.hit_rate_scatter_data(context.project.id, context.opts)
    assert truncated.truncated
    assert truncated.oldest_entry == context.now
    assert length(hd(truncated.series).data) == 10_000
  end

  defp insert(context, metrics, opts \\ []) do
    json = if is_binary(metrics), do: metrics, else: metrics |> CacheMetrics.encode() |> elem(1)
    id = Keyword.get(opts, :id, Ecto.UUID.generate())

    IngestRepo.insert_all(Build, [
      %{
        id: id,
        project_id: context.project.id,
        account_id: context.user.account.id,
        status: "success",
        command: Keyword.get(opts, :command, "build"),
        duration_ms: 100,
        is_ci: Keyword.get(opts, :is_ci, false),
        cache_metrics: json,
        inserted_at: context.now
      }
    ])

    id
  end
end
