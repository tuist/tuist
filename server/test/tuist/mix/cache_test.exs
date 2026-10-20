defmodule Tuist.Mix.CacheTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Mix
  alias Tuist.Mix.Cache
  alias Tuist.Mix.CacheEvent
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :mix)
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    opts = [start_datetime: NaiveDateTime.add(now, -3600), end_datetime: NaiveDateTime.add(now, 60)]
    %{user: user, project: project, now: now, opts: opts}
  end

  test "aggregates lookups, not bypasses, and retains missing versus zero savings", context do
    insert(context, false, [event("jason", "local_hit", 0), event("decimal", "miss"), event("native", "bypass")])
    insert(context, true, [event("jason", "local_hit", 500)])

    assert %{hits: 2, misses: 1, bypasses: 1, hit_rate: rate, saved_duration_ms: 500} =
             Cache.summary(context.project.id, context.opts)

    assert_in_delta rate, 200 / 3, 0.001
    assert %{hit_rate: 50.0, saved_duration_ms: 0} = Cache.summary(context.project.id, context.opts ++ [is_ci: false])
    assert [%{hit_rate: ^rate, saved_duration_ms: 500}] = Cache.timeseries(context.project.id, context.opts)

    assert %{total: 1, rows: [%{dependency: "decimal"}]} =
             Cache.events(context.project.id, context.opts ++ [search: "DECIM"])
  end

  test "project, range and environment scope every read", context do
    other = ProjectsFixtures.project_fixture(account_id: context.user.account.id, build_system: :mix)
    insert(%{context | project: other}, true, [event("secret", "local_hit", 999)])
    insert(%{context | now: NaiveDateTime.add(context.now, -7200)}, false, [event("old", "miss")])
    insert(context, false, [event("mine", "miss")])
    insert(%{context | now: context.opts[:end_datetime]}, false, [event("boundary", "local_hit", 999)])
    assert Cache.hit_rate_analytics(context.project.id, context.opts).metrics.avg == 0.0
    assert %{metrics: %{avg: nil}} = Cache.hit_rate_analytics(context.project.id, context.opts ++ [is_ci: true])
    assert %{hits: 0, misses: 1, saved_duration_ms: nil} = Cache.summary(context.project.id, context.opts)
    assert %{hits: 0, misses: 0, hit_rate: nil} = Cache.summary(context.project.id, context.opts ++ [is_ci: true])
    assert [%{misses: 1}] = Cache.timeseries(context.project.id, context.opts)
    assert %{total: 1, rows: [%{dependency: "mine"}]} = Cache.events(context.project.id, context.opts)
  end

  test "a retried report is counted once", context do
    id = UUIDv7.generate()
    attrs = context |> attributes(false, [event("jason", "local_hit", 10)]) |> Map.put(:id, id)
    assert {:ok, ^id} = Mix.create_build(attrs)
    assert {:ok, ^id} = Mix.create_build(attrs)
    assert %{hits: 1, saved_duration_ms: 10} = Cache.summary(context.project.id, context.opts)
    assert %{metrics: %{avg: 100.0}, series: [%{avg: 100.0}]} = Cache.hit_rate_analytics(context.project.id, context.opts)
    assert %{total: 1} = Cache.events(context.project.id, context.opts)
  end

  test "dashboard averages and percentiles are per-build rates with a real previous-period trend", context do
    insert(context, false, [event("a", "local_hit", 0), event("b", "miss")])
    insert(context, true, [event("a", "local_hit", 0)])

    insert(%{context | now: NaiveDateTime.add(context.now, -4000)}, false, [
      event("a", "local_hit", 0),
      event("b", "miss")
    ])

    insert(context, false, [event("native", "bypass")])
    result = Cache.hit_rate_analytics(context.project.id, context.opts)
    assert result.metrics.avg == 75.0
    assert result.metrics.p99 == 100.0
    assert result.trends.avg == 50.0
    assert [%{avg: 75.0, p99: 100.0}] = result.series
    local = Cache.hit_rate_analytics(context.project.id, context.opts ++ [is_ci: false])
    assert local.metrics.avg == 50.0
    assert local.trends.avg == 0.0
  end

  test "dashboard rates distinguish zero lookups, measured zero, and absent comparisons", context do
    empty = Cache.hit_rate_analytics(context.project.id, context.opts)
    assert empty.metrics.avg == nil
    assert empty.trends.avg == nil
    assert empty.series == []
    insert(context, false, [event("a", "miss")])
    measured = Cache.hit_rate_analytics(context.project.id, context.opts)
    assert measured.metrics.avg == 0.0
    assert measured.metrics.p99 == 0.0
    assert measured.trends.avg == nil
    assert [%{avg: zero}] = measured.series
    assert zero == 0.0
  end

  test "local I/O totals, operation latency and weighted throughput retain their units and scope", context do
    write = Map.merge(event("a", "miss"), %{write_bytes: 2_000, write_duration_us: 20_000})
    read = Map.merge(event("a", "local_hit", 0), %{read_bytes: 1_000, read_duration_us: 5_000})
    attrs = attributes(context, false, [read])
    {:ok, id} = Mix.create_build(attrs)
    {:ok, ^id} = Mix.create_build(attrs)
    insert(context, true, [write])
    insert(context, false, [event("legacy", "local_hit", 0)])
    insert(%{context | now: NaiveDateTime.add(context.now, -4_000)}, false, [read])
    insert(%{context | now: context.opts[:end_datetime]}, false, [write])
    other = ProjectsFixtures.project_fixture(account_id: context.user.account.id, build_system: :mix)
    insert(%{context | project: other}, false, [write])
    result = Cache.io_analytics(context.project.id, context.opts)
    assert result.transfer.metrics["combined"] == 3_000
    assert result.transfer.metrics["downloads"] == 1_000
    assert result.transfer.trends["combined"] == 200.0
    assert result.latency.metrics["combined"] == 12.5
    assert result.throughput.metrics["combined"] == 120_000.0
    assert [%{"combined" => 3_000, "uploads" => 2_000}] = result.transfer.series
    local = Cache.io_analytics(context.project.id, context.opts ++ [is_ci: false])
    assert local.transfer.metrics["combined"] == 1_000
    assert local.transfer.metrics["uploads"] == nil
    assert local.latency.metrics["combined"] == 5.0
  end

  test "local I/O distinguishes unavailable, measured zero and sub-millisecond timings", context do
    assert Cache.io_analytics(context.project.id, context.opts).transfer.metrics["combined"] == nil
    read = Map.merge(event("a", "local_hit", 0), %{read_bytes: 0, read_duration_us: 0})
    insert(context, false, [read])
    result = Cache.io_analytics(context.project.id, context.opts)
    assert result.transfer.metrics["downloads"] == 0
    assert result.latency.metrics["read"] == 0
    assert result.throughput.metrics["downloads"] == nil
    insert(context, false, [Map.merge(read, %{read_bytes: 1, read_duration_us: 100})])
    assert Cache.io_analytics(context.project.id, context.opts).latency.metrics["read"] == 0.05
  end

  test "scatter data has one weighted point per build, excludes non-lookups and deduplicates retries", context do
    attrs =
      attributes(context, false, [event("jason", "local_hit", 0), event("decimal", "miss"), event("native", "bypass")])

    {:ok, local_id} = Mix.create_build(attrs)
    {:ok, ^local_id} = Mix.create_build(attrs)
    {:ok, ci_id} = insert(context, true, [event("jason", "local_hit", 500)])
    insert(context, false, [event("native", "bypass")])
    insert(context, false, [])
    timestamp = context.now |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:millisecond)

    assert %{
             truncated: false,
             oldest_entry: nil,
             series: [
               %{name: false, data: [%{id: ^local_id, value: [^timestamp, 50.0]}]},
               %{name: true, data: [%{id: ^ci_id, value: [^timestamp, 100.0]}]}
             ]
           } = Cache.hit_rate_scatter_data(context.project.id, context.opts)
  end

  test "scatter data is project, environment and half-open period scoped", context do
    other = ProjectsFixtures.project_fixture(account_id: context.user.account.id, build_system: :mix)
    insert(%{context | project: other}, false, [event("secret", "local_hit", 999)])
    insert(%{context | now: Keyword.fetch!(context.opts, :end_datetime)}, false, [event("end", "local_hit")])
    insert(%{context | now: NaiveDateTime.add(context.now, -7200)}, false, [event("old", "local_hit")])

    {:ok, start_id} =
      insert(%{context | now: Keyword.fetch!(context.opts, :start_datetime)}, false, [event("start", "miss")])

    insert(context, true, [event("ci", "local_hit", 0)])

    assert %{series: [%{name: false, data: [%{id: ^start_id, value: [_, rate]}]}]} =
             Cache.hit_rate_scatter_data(context.project.id, context.opts ++ [is_ci: false])

    assert rate == 0.0
  end

  test "scatter data reports truncation only beyond its 10,000-build cap", context do
    row = %{
      project_id: context.project.id,
      dependency: "jason",
      outcome: "miss",
      reason: "",
      key: String.duplicate("a", 64),
      duration_ms: 10,
      saved_duration_ms: nil,
      read_bytes: nil,
      write_bytes: nil,
      read_duration_us: nil,
      write_duration_us: nil,
      read_source: nil,
      write_source: nil,
      is_ci: false,
      mix_env: "dev",
      git_branch: "main",
      inserted_at: DateTime.from_naive!(context.now, "Etc/UTC")
    }

    rows = for _ <- 1..10_000, do: Map.put(row, :build_id, UUIDv7.generate())
    CacheEvent.Buffer.insert_all(rows)

    assert %{truncated: false, oldest_entry: nil, series: [%{data: data}]} =
             Cache.hit_rate_scatter_data(context.project.id, context.opts)

    assert length(data) == 10_000
    CacheEvent.Buffer.insert_all([Map.put(row, :build_id, UUIDv7.generate())])

    assert %{truncated: true, oldest_entry: oldest, series: [%{data: data}]} =
             Cache.hit_rate_scatter_data(context.project.id, context.opts)

    assert length(data) == 10_000
    assert oldest == context.now
  end

  test "recent builds aggregate dependencies, preload runners, and preserve unavailable rates", context do
    {:ok, hit_build} =
      insert(context, false, [event("jason", "local_hit", 500), event("decimal", "miss"), event("native", "bypass")])

    {:ok, bypass_build} = insert(context, false, [event("native", "bypass")])
    {:ok, legacy_build} = insert(context, false, [])
    rows = Cache.recent_builds(context.project.id, context.opts)
    assert length(rows) == 3
    assert Cache.recent_hit_rate(rows) == 50.0
    assert Cache.recent_hit_rate([]) == nil
    by_id = Map.new(rows, &{&1.build.id, &1})
    assert %{cache: %{hit_rate: 50.0, hits: 1, misses: 1, bypasses: 1, saved_duration_ms: 500}} = by_id[hit_build]
    assert by_id[hit_build].build.duration_ms == 10
    assert by_id[hit_build].build.ran_by_account.name == context.user.account.name
    assert %{cache: %{hit_rate: nil}} = by_id[bypass_build]
    assert %{cache: %{hit_rate: nil, hits: 0, misses: 0, bypasses: 0}} = by_id[legacy_build]
  end

  test "recent builds are project, period and environment scoped even when client IDs coincide", context do
    id = UUIDv7.generate()
    other_user = AccountsFixtures.user_fixture(preload: [:account])
    other_project = ProjectsFixtures.project_fixture(account_id: other_user.account.id, build_system: :mix)
    other = %{context | user: other_user, project: other_project}
    {:ok, ^id} = context |> attributes(false, [event("mine", "miss")]) |> Map.put(:id, id) |> Mix.create_build()
    {:ok, ^id} = other |> attributes(false, [event("secret", "local_hit", 999)]) |> Map.put(:id, id) |> Mix.create_build()
    insert(%{context | now: NaiveDateTime.add(context.now, -7200)}, false, [event("old", "local_hit")])
    {:ok, ci_id} = insert(context, true, [event("ci", "local_hit", 0)])

    assert [%{build: %{id: ^id, is_ci: false}, cache: %{hit_rate: local_rate, saved_duration_ms: nil}}] =
             Cache.recent_builds(context.project.id, context.opts ++ [is_ci: false])

    assert local_rate == 0.0

    assert [%{build: %{id: ^ci_id, is_ci: true}, cache: %{hit_rate: 100.0, saved_duration_ms: 0}}] =
             Cache.recent_builds(context.project.id, context.opts ++ [is_ci: true])
  end

  test "recent builds use a half-open time range", context do
    start_datetime = Keyword.fetch!(context.opts, :start_datetime)
    end_datetime = Keyword.fetch!(context.opts, :end_datetime)
    {:ok, start_id} = insert(%{context | now: start_datetime}, false, [event("start", "miss")])
    insert(%{context | now: end_datetime}, false, [event("end", "local_hit")])
    assert [%{build: %{id: ^start_id}}] = Cache.recent_builds(context.project.id, context.opts)
  end

  test "recent builds are bounded, newest first, and deduplicate retries", context do
    ids =
      for index <- 0..8 do
        attrs = attributes(%{context | now: NaiveDateTime.add(context.now, -index * 60)}, false, [event("jason", "miss")])
        {:ok, id} = Mix.create_build(attrs)

        {:ok, ^id} =
          attrs
          |> Map.put(:duration_ms, 100)
          |> Map.update!(:inserted_at, &NaiveDateTime.add(&1, 1))
          |> Mix.create_build()

        id
      end

    rows = Cache.recent_builds(context.project.id, context.opts)
    assert Enum.map(rows, & &1.build.id) == Enum.take(ids, 7)
    assert Enum.all?(rows, &(&1.cache.misses == 1))
    assert Enum.all?(rows, &(&1.build.duration_ms == 100))
  end

  test "build details are identity-scoped and table filters leave summary totals unchanged", context do
    attrs =
      attributes(context, false, [event("jason", "local_hit", 0), event("decimal", "miss"), event("native", "bypass")])

    {:ok, id} = Mix.create_build(attrs)
    {:ok, ^id} = Mix.create_build(attrs)
    other = ProjectsFixtures.project_fixture(account_id: context.user.account.id, build_system: :mix)
    {:ok, ^id} = Mix.create_build(%{attrs | project_id: other.id, dependency_cache: [event("secret", "local_hit", 999)]})
    insert(context, false, [event("other-build", "local_hit", 100)])

    assert %{hits: 1, misses: 1, bypasses: 1, hit_rate: 50.0, saved_duration_ms: 0} =
             Cache.build_summary(context.project.id, id)

    assert %{total: 3, rows: rows} = Cache.build_events(context.project.id, id)
    assert Enum.sort(Enum.map(rows, & &1.dependency)) == ["decimal", "jason", "native"]
    assert %{total: 1, rows: [%{dependency: "jason"}]} = Cache.build_events(context.project.id, id, search: "JASON")
    assert %{total: 1, rows: [%{dependency: "native"}]} = Cache.build_events(context.project.id, id, outcome: "bypass")
    assert %{hit_rate: 50.0} = Cache.build_summary(context.project.id, id)
    assert %{hit_rate: nil, saved_duration_ms: nil} = Cache.build_summary(context.project.id, UUIDv7.generate())
  end

  test "build summary scopes and deduplicates copy totals and latency percentiles", context do
    read = fn name, bytes, duration ->
      Map.merge(event(name, "local_hit", 0), %{read_bytes: bytes, read_duration_us: duration})
    end

    write = Map.merge(event("write", "miss"), %{write_bytes: 3_000, write_duration_us: 20_000})
    attrs = attributes(context, false, [read.("a", 1_000, 5_000), read.("b", 2_000, 10_000), write])
    {:ok, id} = Mix.create_build(attrs)
    {:ok, ^id} = Mix.create_build(attrs)
    other = ProjectsFixtures.project_fixture(account_id: context.user.account.id, build_system: :mix)
    {:ok, ^id} = Mix.create_build(%{attrs | project_id: other.id, dependency_cache: [read.("secret", 999_999, 999_999)]})
    summary = Cache.build_summary(context.project.id, id)
    assert summary.read_bytes == 3_000
    assert summary.write_bytes == 3_000
    assert summary.avg_read_duration_us == 7_500
    assert summary.p99_read_duration_us == 10_000
    assert summary.avg_write_duration_us == 20_000

    assert Enum.map(Cache.build_events(context.project.id, id, sort_order: :desc).rows, & &1.dependency) == [
             "write",
             "b",
             "a"
           ]

    empty = Cache.build_summary(context.project.id, UUIDv7.generate())
    assert empty.read_bytes == nil
    assert empty.avg_read_duration_us == nil
  end

  test "remote dependency restores count as hits with separately identified transport", context do
    remote = Map.merge(event("jason", "remote_hit", 123), %{read_bytes: 2_000, read_duration_us: 50})
    {:ok, id} = Mix.create_build(attributes(context, false, [remote, event("decimal", "miss")]))
    summary = Cache.build_summary(context.project.id, id)
    assert summary.hits == 1
    assert summary.local_hits == 0
    assert summary.remote_hits == 1
    assert summary.hit_rate == 50
    assert summary.saved_duration_ms == 123
    assert summary.read_bytes == 2_000
  end

  test "up-to-date outputs count as local hits without inferred savings or I/O", context do
    current = %{event("current", "local_hit") | reason: "up_to_date", key: ""}
    {:ok, id} = insert(context, false, [current, event("compiled", "miss")])
    summary = Cache.build_summary(context.project.id, id)
    assert summary.local_hits == 1
    assert summary.remote_hits == 0
    assert summary.hit_rate == 50
    assert is_nil(summary.saved_duration_ms)
    assert is_nil(summary.read_bytes)
    assert is_nil(summary.write_bytes)

    assert [%{reason: "up_to_date"}] =
             Enum.filter(Cache.build_events(context.project.id, id).rows, &(&1.dependency == "current"))

    assert Cache.summary(context.project.id, context.opts).hit_rate == 50
    assert Cache.hit_rate_analytics(context.project.id, context.opts).metrics.avg == 50

    for invalid <- [
          %{current | key: String.duplicate("a", 64)},
          %{current | reason: ""},
          %{current | outcome: "miss"},
          %{current | outcome: "remote_hit"},
          %{current | saved_duration_ms: 1},
          Map.merge(current, %{read_bytes: 0, read_duration_us: 0, read_source: "local"}),
          Map.merge(current, %{write_bytes: 0, write_duration_us: 0, write_source: "local"})
        ] do
      assert {:error, :invalid_dependency_cache} = Mix.create_build(attributes(context, false, [invalid]))
    end
  end

  test "retains I/O provenance and rejects mismatched or orphaned sources", context do
    remote = Map.merge(event("remote", "remote_hit", 0), %{read_bytes: 123, read_duration_us: 1, read_source: "remote"})
    local = Map.merge(event("local", "local_hit", 0), %{read_bytes: 0, read_duration_us: 0, read_source: "local"})
    write = Map.merge(event("upload", "miss"), %{write_bytes: 456, write_duration_us: 2, write_source: "remote"})
    {:ok, id} = insert(context, false, [remote, local, write])
    rows = Cache.build_events(context.project.id, id).rows
    assert Enum.find(rows, &(&1.dependency == "remote")).read_source == "remote"
    assert Enum.find(rows, &(&1.dependency == "local")).read_source == "local"
    assert Enum.find(rows, &(&1.dependency == "upload")).write_source == "remote"

    for invalid <- [
          Map.put(remote, :read_source, "local"),
          Map.put(local, :read_source, "remote"),
          Map.put(write, :write_source, "unknown"),
          Map.put(event("missing", "miss"), :write_source, "remote")
        ] do
      assert {:error, _} = Mix.create_build(attributes(context, false, [invalid]))
    end
  end

  test "rejects invalid or duplicate events before storing the build", context do
    for events <- [
          [event("same", "miss"), event("same", "miss")],
          [%{event("a", "miss") | saved_duration_ms: 10}],
          [%{event("a", "miss") | outcome: "unknown_hit"}],
          [%{event("a", "miss") | duration_ms: -1}],
          [%{event("a", "miss") | key: "not-a-digest"}],
          [Map.merge(event("a", "local_hit", 0), %{read_bytes: -1, read_duration_us: 5})],
          [Map.put(event("a", "local_hit", 0), :read_bytes, 5)],
          [Map.merge(event("a", "miss"), %{read_bytes: 5, read_duration_us: 1})],
          [Map.merge(event("a", "bypass"), %{write_bytes: 5, write_duration_us: 1})],
          [Map.merge(event("a", "miss"), %{write_bytes: 9_223_372_036_854_775_808, write_duration_us: 1})]
        ] do
      attrs = attributes(context, false, events)
      assert {:error, :invalid_dependency_cache} = Mix.create_build(attrs)
      assert {:error, :not_found} = Mix.get_build(attrs.id, context.project.id)
    end
  end

  defp event(name, outcome, saved \\ nil) do
    %{
      dependency: name,
      outcome: outcome,
      duration_ms: 1,
      saved_duration_ms: saved,
      key: if(outcome == "bypass", do: "", else: String.duplicate("a", 64)),
      reason: ""
    }
  end

  defp insert(context, ci, events), do: Mix.create_build(attributes(context, ci, events))

  defp attributes(context, ci, events) do
    %{
      id: UUIDv7.generate(),
      project_id: context.project.id,
      account_id: context.user.account.id,
      duration_ms: 10,
      status: "success",
      is_ci: ci,
      inserted_at: context.now,
      dependency_cache: events
    }
  end
end
