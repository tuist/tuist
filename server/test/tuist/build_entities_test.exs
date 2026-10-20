defmodule Tuist.BuildEntitiesTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.BuildEntities
  alias Tuist.BuildEntities.Identity
  alias Tuist.BuildEntities.Observation
  alias Tuist.BuildEntities.QueryLimitError
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Mix
  alias Tuist.OnceEvents
  alias Tuist.Repo
  alias Tuist.ReportActor
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    project = ProjectsFixtures.project_fixture()
    FunWithFlags.enable(:build_entities, for_actor: project)
    end_at = DateTime.new!(Date.utc_today(), ~T[00:00:00])
    start_at = DateTime.add(end_at, -3, :day)
    window = [start_datetime: start_at, end_datetime: end_at]
    %{project: project, start_at: start_at, end_at: end_at, window: window}
  end

  defp observation(project, path, attrs) do
    Map.merge(
      %{
        project_id: project.id,
        system: :mix,
        kind: "file",
        identity: %{"path" => path},
        parent_id: UUIDv7.generate(),
        status: "success",
        cache_status: "none",
        git_branch: "main",
        git_commit_sha: "abc",
        is_ci: true
      },
      Map.new(attrs)
    )
  end

  defp at(start_at, days, seconds \\ 0), do: start_at |> DateTime.add(days, :day) |> DateTime.add(seconds, :second)

  test "disabled projects and the kill switch discard derivation before writing", %{project: project, start_at: start_at} do
    disabled_project = ProjectsFixtures.project_fixture()
    reject(IngestRepo, :insert_all, 2)
    assert :ok = BuildEntities.record([observation(disabled_project, "lib/disabled.ex", observed_at: start_at)])

    assert :disabled =
             BuildEntities.record([observation(disabled_project, "lib/disabled.ex", observed_at: start_at)], sync: true)

    stub(FunWithFlags, :enabled?, fn :build_entities_kill_switch -> true end)
    assert :ok = BuildEntities.record([observation(project, "lib/disabled.ex", observed_at: start_at)])
    refute BuildEntities.enabled?(project)
    refute BuildEntities.enabled?(project.id)
  end

  test "mixed batches write only opted-in projects and check each project once", %{project: project, start_at: start_at} do
    disabled_project = ProjectsFixtures.project_fixture()

    expect(Tuist.FeatureFlags, :build_entities_enabled?, 2, fn id -> id == project.id end)

    expect(IngestRepo, :insert_all, fn Observation, rows ->
      assert length(rows) == 2
      assert Enum.all?(rows, &(&1.project_id == project.id))
      {2, nil}
    end)

    assert :ok =
             BuildEntities.record([
               observation(project, "lib/one.ex", observed_at: start_at),
               observation(disabled_project, "lib/off.ex", observed_at: start_at),
               observation(project, "lib/two.ex", observed_at: start_at)
             ])
  end

  test "records a whole batch with one insert and no catalog or native reads", %{project: project, start_at: start_at} do
    observations =
      for index <- 1..1_000 do
        observation(project, "lib/file_#{index}.ex", observed_at: at(start_at, 1), duration_ms: index)
      end

    for arity <- [1, 2] do
      reject(ClickHouseRepo, :all, arity)
      reject(ClickHouseRepo, :one, arity)
      reject(Repo, :all, arity)
      reject(Repo, :one, arity)
    end

    for arity <- [2, 3], do: reject(ClickHouseRepo, :query, arity)

    expect(IngestRepo, :insert_all, fn Observation, rows ->
      assert length(rows) == 1_000
      assert length(Enum.uniq_by(rows, & &1.entity_id)) == 1_000
      assert Enum.all?(rows, &(&1.system == "mix" and &1.kind == "file" and &1.project_id == project.id))
      {length(rows), nil}
    end)

    assert :ok = BuildEntities.record(observations)
    assert :ok = BuildEntities.record([])
  end

  test "duplicate inserts do not change counts or distributions", %{project: project, start_at: start_at, window: window} do
    observations =
      for {duration, index} <- Enum.with_index([100, 200, 300]) do
        observation(project, "lib/a.ex", duration_ms: duration, observed_at: at(start_at, 1, index))
      end

    BuildEntities.record(observations)
    id = Identity.id(project.id, :mix, "file", %{"path" => "lib/a.ex"})
    single = BuildEntities.analytics(project.id, :mix, "file", id, window)

    BuildEntities.record(observations)
    BuildEntities.record(observations)

    assert BuildEntities.analytics(project.id, :mix, "file", id, window) == single
    assert single.total.observations == 3
    assert single.total.avg_duration_ms == 200
    assert single.total.p50_duration_ms == 200
    assert single.total.p90_duration_ms == 280
    assert single.total.hit_rate == nil

    {history, meta} = BuildEntities.history(project.id, :mix, "file", id, window)
    assert length(history) == 3
    assert meta.total_count == 3

    {[entry], _meta} = BuildEntities.list(project.id, :mix, "file", window)
    assert entry.observations == 3
  end

  test "replacement reads resolve cross-month corrections before cohort filters", %{
    project: project,
    start_at: start_at,
    window: window
  } do
    previous_month = Date.utc_today() |> Date.beginning_of_month() |> Date.add(-1) |> DateTime.new!(~T[23:59:59.000000])

    original =
      observation(project, "lib/cross_month.ex", duration_ms: 200, observed_at: at(start_at, 1), cache_status: "miss")

    expect(IngestRepo, :insert_all, fn schema, rows ->
      rows = Enum.map(rows, &Map.put(&1, :inserted_at, DateTime.to_naive(previous_month)))
      Mimic.call_original(IngestRepo, :insert_all, [schema, rows])
    end)

    BuildEntities.record([original])
    stub(IngestRepo, :insert_all, fn schema, rows -> Mimic.call_original(IngestRepo, :insert_all, [schema, rows]) end)
    corrected = %{original | duration_ms: nil, git_branch: "corrected", is_ci: nil, cache_status: "none"}
    BuildEntities.record([corrected])

    assert %{rows: [[2]]} =
             IngestRepo.query!(
               "SELECT uniqExact(_partition_id) FROM build_entity_observations WHERE project_id = {project_id:Int64}",
               %{project_id: project.id}
             )

    # A delayed older version must not win even when it is written last.
    expect(IngestRepo, :insert_all, fn schema, rows ->
      rows = Enum.map(rows, &Map.put(&1, :inserted_at, DateTime.to_naive(previous_month)))
      Mimic.call_original(IngestRepo, :insert_all, [schema, rows])
    end)

    BuildEntities.record([original])
    id = Identity.id(project.id, :mix, "file", original.identity)

    assert {[%{duration_ms: nil, git_branch: "corrected", is_ci: nil}], %{total_count: 1}} =
             BuildEntities.history(project.id, :mix, "file", id, window)

    assert {[], _meta} = BuildEntities.history(project.id, :mix, "file", id, window ++ [branch: "main"])
    assert {[], _meta} = BuildEntities.list(project.id, :mix, "file", window ++ [environment: "ci"])

    assert %{total: %{observations: 1, duration_samples: 0, misses: 0, avg_duration_ms: nil}} =
             BuildEntities.analytics(project.id, :mix, "file", id, window)

    assert %{rows: []} = BuildEntities.duration_scatter(project.id, :mix, "file", id, window)
    stub(IngestRepo, :insert_all, fn schema, rows -> Mimic.call_original(IngestRepo, :insert_all, [schema, rows]) end)
    BuildEntities.record([%{corrected | observed_at: at(start_at, -1)}])
    assert {[], %{total_count: 0}} = BuildEntities.history(project.id, :mix, "file", id, window)

    assert %{total: %{observations: 0}, previous: %{observations: 1, duration_samples: 0}} =
             BuildEntities.analytics(project.id, :mix, "file", id, window)
  end

  test "a replay that moves an observation counts only where its latest version is", %{
    project: project,
    start_at: start_at,
    window: window
  } do
    original = observation(project, "lib/a.ex", observed_at: at(start_at, 1), duration_ms: 10, is_ci: true)
    BuildEntities.record([original])
    BuildEntities.record([%{original | observed_at: at(start_at, -1), is_ci: false}])
    id = Identity.id(project.id, :mix, "file", %{"path" => "lib/a.ex"})

    analytics = BuildEntities.analytics(project.id, :mix, "file", id, window)
    assert analytics.total.observations == 0
    assert analytics.previous.observations == 1

    assert {[], %{total_count: 0}} = BuildEntities.history(project.id, :mix, "file", id, window)
    assert {[%{observations: 0}], _meta} = BuildEntities.list(project.id, :mix, "file", window)
    assert {[], _meta} = BuildEntities.list(project.id, :mix, "file", window ++ [environment: "ci"])

    previous_window = [start_datetime: DateTime.add(start_at, -3, :day), end_datetime: start_at]

    assert {[%{is_ci: false}], _meta} =
             BuildEntities.history(project.id, :mix, "file", id, previous_window ++ [environment: "local"])
  end

  test "a replay that changes an observation's cohort counts only in its latest cohort", %{
    project: project,
    start_at: start_at,
    window: window
  } do
    original = observation(project, "lib/a.ex", observed_at: at(start_at, 1), duration_ms: 10, git_branch: "main")
    BuildEntities.record([original])
    BuildEntities.record([%{original | git_branch: "feature", is_ci: false}])
    id = Identity.id(project.id, :mix, "file", %{"path" => "lib/a.ex"})

    assert {[], %{total_count: 0}} = BuildEntities.history(project.id, :mix, "file", id, window ++ [branch: "main"])
    assert {[], _meta} = BuildEntities.list(project.id, :mix, "file", window ++ [branch: "main"])
    assert {[], _meta} = BuildEntities.list(project.id, :mix, "file", window ++ [environment: "ci"])

    assert {[%{git_branch: "feature", is_ci: false}], %{total_count: 1}} =
             BuildEntities.history(project.id, :mix, "file", id, window ++ [branch: "feature"])

    assert {[%{observations: 1}], _meta} =
             BuildEntities.list(project.id, :mix, "file", window ++ [branch: "feature", environment: "local"])

    assert %{observations: 0} = BuildEntities.analytics(project.id, :mix, "file", id, window ++ [branch: "main"]).total
    assert %{observations: 1} = BuildEntities.analytics(project.id, :mix, "file", id, window).total
  end

  test "reads run under explicit limits and raise QueryLimitError when ClickHouse enforces them", %{
    project: project,
    window: window
  } do
    test_pid = self()
    id = Identity.id(project.id, :mix, "file", %{"path" => "lib/a.ex"})

    stub(ClickHouseRepo, :query, fn _sql, _params, opts ->
      send(test_pid, {:query_opts, opts})
      {:error, %Ch.Error{code: 241, message: "Memory limit exceeded"}}
    end)

    assert_raise QueryLimitError, "Memory limit exceeded", fn ->
      BuildEntities.history(project.id, :mix, "file", id, window)
    end

    assert_received {:query_opts, opts}
    assert Keyword.fetch!(opts, :timeout) == 25_000

    assert Keyword.fetch!(opts, :settings) == [
             max_threads: 2,
             max_memory_usage: 256 * 1024 * 1024,
             max_bytes_before_external_group_by: 64 * 1024 * 1024,
             max_bytes_before_external_sort: 64 * 1024 * 1024,
             optimize_aggregation_in_order: 1,
             aggregation_in_order_max_block_bytes: 1024 * 1024,
             max_block_size: 8192,
             max_streams_to_max_threads_ratio: 1,
             max_execution_time: 20,
             do_not_merge_across_partitions_select_final: 0,
             optimize_move_to_prewhere_if_final: 0,
             use_skip_indexes_if_final: 0
           ]

    stub(ClickHouseRepo, :query, fn _sql, _params, opts ->
      send(test_pid, {:query_opts, opts})
      {:error, %Ch.Error{code: 159}}
    end)

    assert %QueryLimitError{code: 159} = catch_error(BuildEntities.list(project.id, :mix, "file", window))
    assert_received {:query_opts, opts}
    assert Keyword.fetch!(opts, :timeout) == 35_000
    assert Keyword.fetch!(opts, :settings)[:max_memory_usage] == 512 * 1024 * 1024
    assert Keyword.fetch!(opts, :settings)[:max_bytes_before_external_group_by] == 128 * 1024 * 1024
  end

  test "all observation read paths preserve FINAL and replacement safety settings", %{project: project, window: window} do
    :ok = BuildEntities.record([observation(project, "lib/invariants.ex", observed_at: window[:start_datetime])])
    id = Identity.id(project.id, :mix, "file", %{"path" => "lib/invariants.ex"})
    test_pid = self()

    stub(ClickHouseRepo, :query, fn sql, params, opts ->
      settings = Keyword.fetch!(opts, :settings)
      assert settings[:do_not_merge_across_partitions_select_final] == 0
      assert settings[:optimize_move_to_prewhere_if_final] == 0
      assert settings[:use_skip_indexes_if_final] == 0

      if String.contains?(sql, "build_entity_observations") do
        assert String.contains?(sql, "FROM build_entity_observations FINAL")
        assert String.contains?(sql, "PREWHERE project_id =")
        send(test_pid, :checked_observation_query)
      end

      Mimic.call_original(ClickHouseRepo, :query, [sql, params, opts])
    end)

    BuildEntities.list(project.id, :mix, "file", window)
    BuildEntities.list(project.id, :mix, "file", window ++ [environment: "ci"])
    BuildEntities.get(project.id, :mix, "file", id)
    BuildEntities.history(project.id, :mix, "file", id, window)
    BuildEntities.analytics(project.id, :mix, "file", id, window)
    BuildEntities.duration_scatter(project.id, :mix, "file", id, window)
    assert_received :checked_observation_query
  end

  test "other database errors are not turned into query limit errors", %{project: project, window: window} do
    id = Identity.id(project.id, :mix, "file", %{"path" => "lib/a.ex"})

    stub(ClickHouseRepo, :query, fn _sql, _params, _opts ->
      {:error, %Ch.Error{code: 60, message: "Unknown table"}}
    end)

    assert_raise Ch.Error, "Unknown table", fn -> BuildEntities.get(project.id, :mix, "file", id) end
    assert_raise MatchError, fn -> BuildEntities.history(project.id, :mix, "file", id, window) end
  end

  test "an all-hit cohort has a 100% hit rate and an uncacheable one has none", %{
    project: project,
    start_at: start_at,
    window: window
  } do
    BuildEntities.record([
      observation(project, "lib/a.ex", observed_at: at(start_at, 1), cache_status: "hit_local"),
      observation(project, "lib/a.ex", observed_at: at(start_at, 1, 1), cache_status: "hit_remote"),
      observation(project, "lib/a.ex", observed_at: at(start_at, 1, 2), cache_status: "write"),
      observation(project, "lib/b.ex", observed_at: at(start_at, 1), cache_status: "none")
    ])

    hits =
      BuildEntities.analytics(
        project.id,
        :mix,
        "file",
        Identity.id(project.id, :mix, "file", %{"path" => "lib/a.ex"}),
        window
      )

    assert %{observations: 3, hits: 2, misses: 0, hit_rate: 100.0} = hits.total

    none =
      BuildEntities.analytics(
        project.id,
        :mix,
        "file",
        Identity.id(project.id, :mix, "file", %{"path" => "lib/b.ex"}),
        window
      )

    assert %{observations: 1, hits: 0, misses: 0, hit_rate: nil} = none.total
  end

  test "unrecognized statuses are unknown, not successful", %{project: project, start_at: start_at, window: window} do
    BuildEntities.record([observation(project, "lib/a.ex", observed_at: at(start_at, 1), status: "exploded")])
    id = Identity.id(project.id, :mix, "file", %{"path" => "lib/a.ex"})

    assert {[%{status: "unknown"}], _meta} = BuildEntities.history(project.id, :mix, "file", id, window)
  end

  test "get returns the catalog entity and rejects other projects and invalid kinds", %{
    project: project,
    start_at: start_at
  } do
    BuildEntities.record([observation(project, "lib/a.ex", observed_at: at(start_at, 1))])
    id = Identity.id(project.id, :mix, "file", %{"path" => "lib/a.ex"})
    other = ProjectsFixtures.project_fixture()

    assert {:ok, entity} = BuildEntities.get(project.id, :mix, "file", id)
    assert entity.id == id
    assert entity.name == "lib/a.ex"
    assert entity.identity == %{"path" => "lib/a.ex"}
    assert DateTime.compare(entity.first_seen_at, at(start_at, 1)) == :eq
    assert entity |> Map.keys() |> Enum.sort() == [:first_seen_at, :id, :identity, :last_seen_at, :name]

    assert {:error, :not_found} = BuildEntities.get(other.id, :mix, "file", id)
    assert {:error, :not_found} = BuildEntities.get(project.id, :mix, "module", id)
    assert {:error, :not_found} = BuildEntities.get(project.id, :mix, "unknown", id)
    assert {:error, :not_found} = BuildEntities.get(project.id, :mix, "file", "not-a-uuid")
  end

  test "the catalog keeps the name of the latest observed execution, not the latest insert", %{
    project: project,
    start_at: start_at
  } do
    identity = %{"target_id" => "//app", "capability" => "build", "action_index" => "0"}
    newer = observation(project, "", system: :once, kind: "action", identity: identity, name: "Compile app")
    older = observation(project, "", system: :once, kind: "action", identity: identity, name: "Old label")

    BuildEntities.record([Map.put(newer, :observed_at, at(start_at, 2))])
    BuildEntities.record([Map.put(older, :observed_at, at(start_at, 1))])

    id = Identity.id(project.id, :once, "action", identity)
    assert {:ok, %{name: "Compile app"} = entity} = BuildEntities.get(project.id, :once, "action", id)
    assert DateTime.compare(entity.first_seen_at, at(start_at, 1)) == :eq
    assert DateTime.compare(entity.last_seen_at, at(start_at, 2)) == :eq
  end

  test "list sorts, searches, filters by environment and paginates", %{
    project: project,
    start_at: start_at,
    window: window
  } do
    BuildEntities.record([
      observation(project, "lib/a.ex", observed_at: at(start_at, 1), is_ci: true),
      observation(project, "lib/b.ex", observed_at: at(start_at, 2), is_ci: false),
      observation(project, "lib/c.ex", observed_at: at(start_at, 0), is_ci: true)
    ])

    {entries, meta} = BuildEntities.list(project.id, :mix, "file", window)
    assert Enum.map(entries, & &1.name) == ["lib/b.ex", "lib/a.ex", "lib/c.ex"]

    assert meta == %{
             has_next_page: false,
             has_previous_page: false,
             current_page: 1,
             page_size: 20,
             total_count: 3,
             total_pages: 1
           }

    {entries, _meta} = BuildEntities.list(project.id, :mix, "file", window ++ [sort_by: "name", sort_order: "asc"])
    assert Enum.map(entries, & &1.name) == ["lib/a.ex", "lib/b.ex", "lib/c.ex"]

    {entries, _meta} = BuildEntities.list(project.id, :mix, "file", window ++ [environment: "ci", sort_by: "name"])
    assert Enum.map(entries, & &1.name) == ["lib/c.ex", "lib/a.ex"]

    {[%{name: "lib/b.ex"}], _meta} = BuildEntities.list(project.id, :mix, "file", window ++ [search: "B.EX"])

    {[_], meta} = BuildEntities.list(project.id, :mix, "file", window ++ [page: 2, page_size: 2])
    assert %{current_page: 2, has_previous_page: true, has_next_page: false, total_pages: 2} = meta

    assert {[], %{total_count: 0}} = BuildEntities.list(project.id, :mix, "task", window)
  end

  test "filtered inventory counts in one scan and paginates catalog candidates without false matches", %{
    project: project,
    start_at: start_at,
    end_at: end_at,
    window: window
  } do
    corrected = observation(project, "lib/shared/a.ex", observed_at: at(start_at, 1))

    BuildEntities.record([
      observation(project, "lib/shared/a.ex", observed_at: at(start_at, 1)),
      observation(project, "lib/shared/a.ex", observed_at: at(start_at, 2)),
      corrected,
      observation(project, "lib/shared/b.ex", observed_at: at(start_at, 1)),
      observation(project, "lib/shared/outside.ex", observed_at: at(start_at, -1)),
      observation(project, "lib/shared/bridge.ex", observed_at: at(start_at, -1)),
      observation(project, "lib/shared/bridge.ex", observed_at: end_at)
    ])

    BuildEntities.record([%{corrected | is_ci: false, git_branch: "feature"}])

    caller = self()

    stub(ClickHouseRepo, :query, fn sql, params, opts ->
      send(caller, :inventory_query)
      Mimic.call_original(ClickHouseRepo, :query, [sql, params, opts])
    end)

    filters =
      window ++ [environment: "ci", branch: "main", search: "shared", sort_by: "name", sort_order: "asc", page_size: 1]

    assert {[%{name: "lib/shared/a.ex", observations: 2}], %{total_count: 2, has_next_page: true}} =
             BuildEntities.list(project.id, :mix, "file", filters)

    assert_receive :inventory_query
    refute_receive :inventory_query, 0

    assert {[%{name: "lib/shared/b.ex", observations: 1}], %{total_count: 2, has_previous_page: true}} =
             BuildEntities.list(project.id, :mix, "file", filters ++ [page: 2])

    assert {[], %{total_count: 2, total_pages: 2}} = BuildEntities.list(project.id, :mix, "file", filters ++ [page: 3])

    assert {[], %{total_count: 0}} =
             BuildEntities.list(project.id, :mix, "file", Keyword.put(filters, :search, "missing"))
  end

  test "history searches recorded references and filters the latest outcomes before pagination", %{
    project: project,
    start_at: start_at,
    window: window
  } do
    original =
      observation(project, "lib/a.ex",
        observed_at: at(start_at, 1),
        status: "failure",
        cache_status: "miss",
        git_branch: "feature/old",
        git_commit_sha: "DEADBEEF"
      )

    BuildEntities.record([original])
    BuildEntities.record([%{original | status: "success", git_branch: "feature/current", cache_status: "hit_remote"}])

    BuildEntities.record([
      observation(project, "lib/a.ex",
        observed_at: at(start_at, 1, 1),
        status: "failure",
        cache_status: "miss",
        git_branch: "main",
        git_commit_sha: "other"
      )
    ])

    id = Identity.id(project.id, :mix, "file", %{"path" => "lib/a.ex"})

    for search <- ["deadbeef", "FEATURE/current", original.parent_id] do
      assert {[%{status: "success", cache_status: "hit_remote"}], %{total_count: 1}} =
               BuildEntities.history(project.id, :mix, "file", id, window ++ [search: search, page_size: 1])
    end

    assert {[], %{total_count: 0}} =
             BuildEntities.history(project.id, :mix, "file", id, window ++ [search: "feature/old"])

    filters = [
      %{field: :git_branch, op: :=~, value: "FEATURE/"},
      %{field: :status, op: :!=, value: "failure"},
      %{field: :cache_status, op: :==, value: "hit_remote"}
    ]

    assert {[%{git_branch: "feature/current"}], %{total_count: 1}} =
             BuildEntities.history(project.id, :mix, "file", id, window ++ [filters: filters])

    assert {[%{git_branch: "main"}], %{total_count: 1}} =
             BuildEntities.history(
               project.id,
               :mix,
               "file",
               id,
               window ++ [filters: [%{field: :git_branch, op: :not_ilike, value: "feature/"}]]
             )
  end

  test "history sorts complete cohorts, with missing durations last and stable numbered pages", %{
    project: project,
    start_at: start_at,
    window: window
  } do
    BuildEntities.record(
      for {duration, index} <- Enum.with_index([100, nil, 300, 100, 200]),
          do: observation(project, "lib/a.ex", observed_at: at(start_at, 1, index), duration_ms: duration)
    )

    id = Identity.id(project.id, :mix, "file", %{"path" => "lib/a.ex"})

    for {order, expected} <- [{"asc", [100, 100, 200, 300, nil]}, {"desc", [300, 200, 100, 100, nil]}] do
      rows =
        for page <- 1..3, reduce: [] do
          rows ->
            {entries, meta} =
              BuildEntities.history(
                project.id,
                :mix,
                "file",
                id,
                window ++ [sort_by: "duration_ms", sort_order: order, page: page, page_size: 2]
              )

            assert meta.total_count == 5
            assert meta.current_page == page
            assert meta.after == nil
            assert meta.before == nil
            rows ++ entries
        end

      assert Enum.map(rows, & &1.duration_ms) == expected
      assert length(Enum.uniq_by(rows, & &1.id)) == 5
    end

    {oldest, _} = BuildEntities.history(project.id, :mix, "file", id, window ++ [sort_order: "asc"])
    assert Enum.map(oldest, & &1.duration_ms) == [100, nil, 300, 100, 200]

    {safe, _} =
      BuildEntities.history(project.id, :mix, "file", id, window ++ [sort_by: "id; DROP TABLE", sort_order: "invalid"])

    assert Enum.map(safe, & &1.duration_ms) == [200, 100, 300, nil, 100]
  end

  test "history pages by page number and by keyset cursors", %{project: project, start_at: start_at, window: window} do
    observations =
      for index <- 0..4 do
        observation(project, "lib/a.ex", observed_at: at(start_at, 1, index), duration_ms: index)
      end

    BuildEntities.record(observations)
    id = Identity.id(project.id, :mix, "file", %{"path" => "lib/a.ex"})

    {first, meta} = BuildEntities.history(project.id, :mix, "file", id, window ++ [page_size: 2])
    assert Enum.map(first, & &1.duration_ms) == [4, 3]
    assert %{has_next_page: true, has_previous_page: false, total_count: 5, before: nil} = meta

    {second, meta} = BuildEntities.history(project.id, :mix, "file", id, window ++ [page_size: 2, after: meta.after])
    assert Enum.map(second, & &1.duration_ms) == [2, 1]
    assert %{current_page: nil, has_next_page: true, has_previous_page: true} = meta

    {back, _meta} = BuildEntities.history(project.id, :mix, "file", id, window ++ [page_size: 2, before: meta.before])
    assert Enum.map(back, & &1.duration_ms) == [4, 3]

    {[_], _meta} = BuildEntities.history(project.id, :mix, "file", id, window ++ [page: 3, page_size: 2])

    assert [%{parent_id: parent_id, status: "success", cache_status: "none", is_ci: true, git_branch: "main"} | _] = first
    assert is_binary(parent_id)
  end

  test "analytics compares with the previous window and fills empty days", %{
    project: project,
    start_at: start_at,
    window: window
  } do
    identity = %{"path" => "lib/cache_math.ex"}
    base = observation(project, "lib/cache_math.ex", identity: identity, git_branch: "main")

    BuildEntities.record([
      Map.merge(base, %{cache_status: "hit_remote", duration_ms: 10, observed_at: at(start_at, 0), discriminator: 1}),
      Map.merge(base, %{cache_status: "miss", duration_ms: 30, observed_at: at(start_at, 2), discriminator: 2}),
      Map.merge(base, %{cache_status: "miss", status: "failure", observed_at: at(start_at, -1), discriminator: 3}),
      Map.merge(base, %{cache_status: "hit_remote", observed_at: at(start_at, 2), git_branch: "other", discriminator: 4})
    ])

    id = Identity.id(project.id, :mix, "file", identity)
    analytics = BuildEntities.analytics(project.id, :mix, "file", id, window ++ [branch: "main"])

    assert analytics.total == %{
             observations: 2,
             hits: 1,
             misses: 1,
             hit_rate: 50.0,
             failures: 0,
             duration_samples: 2,
             avg_duration_ms: 20,
             p50_duration_ms: 20,
             p90_duration_ms: 28,
             p99_duration_ms: 30
           }

    assert %{observations: 1, misses: 1, failures: 1, duration_samples: 0, avg_duration_ms: nil} = analytics.previous
    assert analytics.previous.hit_rate == 0.0

    assert Enum.map(analytics.points, &{&1.date, &1.observations}) == [
             {Date.to_iso8601(DateTime.to_date(start_at)), 1},
             {start_at |> DateTime.add(1, :day) |> DateTime.to_date() |> Date.to_iso8601(), 0},
             {start_at |> DateTime.add(2, :day) |> DateTime.to_date() |> Date.to_iso8601(), 1}
           ]

    misses = BuildEntities.analytics(project.id, :mix, "file", id, window ++ [cache_status: "miss"])
    assert %{observations: 1, avg_duration_ms: 30} = misses.total
  end

  describe "duration samples" do
    test "count measured observations, so a true zero differs from no measurement", %{
      project: project,
      start_at: start_at,
      window: window
    } do
      BuildEntities.record([
        observation(project, "lib/zero.ex", observed_at: at(start_at, 1), duration_ms: 0),
        observation(project, "lib/unmeasured.ex", observed_at: at(start_at, 1)),
        observation(project, "lib/unmeasured.ex", observed_at: at(start_at, 1, 1))
      ])

      zero = BuildEntities.analytics(project.id, :mix, "file", file_id(project, "lib/zero.ex"), window)
      assert %{observations: 1, duration_samples: 1, avg_duration_ms: 0, p50_duration_ms: 0} = zero.total

      unmeasured = BuildEntities.analytics(project.id, :mix, "file", file_id(project, "lib/unmeasured.ex"), window)
      assert %{observations: 2, duration_samples: 0, avg_duration_ms: nil, p99_duration_ms: nil} = unmeasured.total
      assert %{observations: 0, duration_samples: 0} = unmeasured.previous

      assert Enum.map(unmeasured.points, &{&1.observations, &1.duration_samples}) == [{0, 0}, {2, 0}, {0, 0}]

      assert %{total: %{duration_samples: 0}, previous: %{duration_samples: 0}, points: []} =
               BuildEntities.analytics(project.id, :mix, "unknown", file_id(project, "lib/zero.ex"), window)
    end
  end

  describe "duration_scatter/5" do
    test "returns measured observations newest first", %{project: project, start_at: start_at, window: window} do
      BuildEntities.record([
        observation(project, "lib/a.ex", observed_at: at(start_at, 0), duration_ms: 10),
        observation(project, "lib/a.ex", observed_at: at(start_at, 2), duration_ms: 30),
        observation(project, "lib/a.ex", observed_at: at(start_at, 1), duration_ms: 0),
        observation(project, "lib/a.ex", observed_at: at(start_at, 1, 1)),
        observation(project, "lib/a.ex", observed_at: at(start_at, -1), duration_ms: 99)
      ])

      assert %{rows: rows, truncated: false, oldest_entry: oldest_entry} =
               BuildEntities.duration_scatter(project.id, :mix, "file", file_id(project, "lib/a.ex"), window)

      assert Enum.map(rows, & &1.duration_ms) == [30, 0, 10]
      assert NaiveDateTime.compare(oldest_entry, start_at |> at(0) |> DateTime.to_naive()) == :eq

      assert [%{id: id, parent_id: parent_id, status: "success", cache_status: "none", is_ci: true} | _] = rows
      assert is_binary(id) and is_binary(parent_id)
    end

    test "resolves the latest version before filtering, so replays that clear or move a duration are not plotted",
         %{project: project, start_at: start_at, window: window} do
      cleared = observation(project, "lib/a.ex", observed_at: at(start_at, 1), duration_ms: 10)
      moved = observation(project, "lib/a.ex", observed_at: at(start_at, 1, 1), duration_ms: 20, git_branch: "main")
      BuildEntities.record([cleared, moved])
      BuildEntities.record([%{cleared | duration_ms: nil}, %{moved | git_branch: "feature", is_ci: false}])
      id = file_id(project, "lib/a.ex")

      assert %{rows: [%{duration_ms: 20, git_branch: "feature"}]} =
               BuildEntities.duration_scatter(project.id, :mix, "file", id, window)

      assert %{rows: [], oldest_entry: nil} =
               BuildEntities.duration_scatter(project.id, :mix, "file", id, window ++ [branch: "main"])

      assert %{rows: []} = BuildEntities.duration_scatter(project.id, :mix, "file", id, window ++ [environment: "ci"])

      assert %{rows: [%{duration_ms: 20}]} =
               BuildEntities.duration_scatter(project.id, :mix, "file", id, window ++ [environment: "local"])

      analytics = BuildEntities.analytics(project.id, :mix, "file", id, window)
      assert %{observations: 2, duration_samples: 1} = analytics.total
    end

    test "is scoped to the project, system and kind", %{project: project, start_at: start_at, window: window} do
      BuildEntities.record([observation(project, "lib/a.ex", observed_at: at(start_at, 1), duration_ms: 10)])
      id = file_id(project, "lib/a.ex")
      other = ProjectsFixtures.project_fixture()
      empty = %{rows: [], truncated: false, oldest_entry: nil}

      assert BuildEntities.duration_scatter(other.id, :mix, "file", id, window) == empty
      assert BuildEntities.duration_scatter(project.id, :mix, "module", id, window) == empty
      assert BuildEntities.duration_scatter(project.id, :gradle, "file", id, window) == empty
      assert BuildEntities.duration_scatter(project.id, :mix, "file", "not-a-uuid", window) == empty
    end

    test "reports truncation when older measured observations are left out", %{
      project: project,
      start_at: start_at,
      window: window
    } do
      BuildEntities.record(
        for seconds <- 0..2 do
          observation(project, "lib/a.ex", observed_at: at(start_at, 1, seconds), duration_ms: seconds)
        end
      )

      id = file_id(project, "lib/a.ex")

      assert %{rows: [%{duration_ms: 2}, %{duration_ms: 1}], truncated: true, oldest_entry: oldest_entry} =
               BuildEntities.duration_scatter(project.id, :mix, "file", id, window ++ [limit: 2])

      assert NaiveDateTime.compare(oldest_entry, start_at |> at(1, 1) |> DateTime.to_naive()) == :eq

      assert %{rows: [_, _, _], truncated: false} =
               BuildEntities.duration_scatter(project.id, :mix, "file", id, window ++ [limit: 3])
    end

    test "runs under the entity read limits, caps the limit and raises QueryLimitError", %{
      project: project,
      window: window
    } do
      test_pid = self()
      id = file_id(project, "lib/a.ex")

      stub(ClickHouseRepo, :query, fn _sql, params, opts ->
        send(test_pid, {:scatter_query, params, opts})
        {:error, %Ch.Error{code: 159, message: "Timeout exceeded"}}
      end)

      assert_raise QueryLimitError, "Timeout exceeded", fn ->
        BuildEntities.duration_scatter(project.id, :mix, "file", id, window ++ [limit: 50_000])
      end

      assert_received {:scatter_query, params, opts}
      assert params.limit == 10_001
      assert Keyword.fetch!(opts, :timeout) == 25_000
      assert Keyword.fetch!(opts, :settings)[:max_memory_usage] == 256 * 1024 * 1024
    end
  end

  describe "parent_actor_names/4" do
    setup %{project: project} do
      actor = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture()
      other_project = ProjectsFixtures.project_fixture()

      %{
        actor: actor,
        actor_name: actor.account.name,
        owner_account_id: project.account_id,
        organization_account_id: organization.account.id,
        other_project: other_project
      }
    end

    test "explicit provenance separates verified actors from publishers and opaque claims", %{
      project: project,
      actor: publisher
    } do
      verified_actor = AccountsFixtures.user_fixture(preload: [:account])

      for {system, kind} <- [{:gradle, "task"}, {:mix, "file"}, {:mix, "module"}, {:xcode, "module"}] do
        create = fn attrs ->
          case system do
            :gradle ->
              GradleFixtures.build_fixture([project_id: project.id, account_id: publisher.account.id] ++ attrs)

            :mix ->
              mix_build(project.id, publisher.account.id, Map.new(attrs))

            :xcode ->
              CommandEventsFixtures.command_event_fixture(
                [project_id: project.id, name: "generate", user_id: publisher.id] ++ attrs
              ).id
          end
        end

        legacy = create.([])
        verified = create.(submission_auth: "token", actor_account_id: verified_actor.account.id)
        unknown = create.(submission_auth: "token")
        reported = create.(submission_auth: "network_trusted", claimed_actor_id: "reported-person")
        ids = [legacy, verified, unknown, reported]

        assert BuildEntities.parent_actor_names(project.id, system, kind, ids) ==
                 %{legacy => publisher.account.name, verified => verified_actor.account.name}

        contexts = BuildEntities.parent_contexts(project.id, system, kind, ids)
        assert ReportActor.actor(contexts[verified]).source == :verified
        assert ReportActor.actor(contexts[unknown]).source == :unknown
        assert ReportActor.actor(contexts[reported]).source == :reported
        assert ReportActor.actor(contexts[reported]).name == "reported-person"
        assert contexts[unknown].ran_by_name == nil
        assert contexts[reported].ran_by_name == nil

        {table, version, publisher_column, publisher_id} =
          case system do
            :gradle -> {"gradle_builds", "inserted_at", "account_id", publisher.account.id}
            :mix -> {"mix_builds", "inserted_at", "account_id", publisher.account.id}
            :xcode -> {"command_events", "updated_at", "user_id", publisher.id}
          end

        for id <- [verified, reported] do
          IngestRepo.query!(
            """
            INSERT INTO #{table} (
              id, project_id, #{publisher_column}, actor_account_id,
              claimed_actor_id, submission_auth, #{version}
            )
            SELECT {id:UUID}, {project_id:Int64}, {publisher_id:Int64}, 0, '', 'token', now() + INTERVAL 1 DAY
            """,
            %{id: id, project_id: project.id, publisher_id: publisher_id}
          )
        end

        assert BuildEntities.parent_actor_names(project.id, system, kind, [verified, reported]) == %{}
        cleared = BuildEntities.parent_contexts(project.id, system, kind, [verified, reported])
        assert ReportActor.actor(cleared[verified]).source == :unknown
        assert ReportActor.actor(cleared[reported]).source == :unknown
      end
    end

    test "maps Gradle builds to the user account that ran them", context do
      %{project: project, actor: actor, actor_name: actor_name} = context

      ran = gradle_build(project.id, actor.account.id)
      by_owner = gradle_build(project.id, context.owner_account_id)
      by_organization = gradle_build(project.id, context.organization_account_id)
      by_deleted = gradle_build(project.id, 999_999_999)
      unattributed = gradle_build(project.id, 0)
      elsewhere = gradle_build(context.other_project.id, actor.account.id)

      ids = [
        ran,
        String.upcase(ran),
        by_owner,
        by_organization,
        by_deleted,
        unattributed,
        elsewhere,
        UUIDv7.generate(),
        "not-a-uuid",
        ""
      ]

      assert BuildEntities.parent_actor_names(project.id, :gradle, "task", ids) ==
               %{ran => actor_name, String.upcase(ran) => actor_name}
    end

    test "reports the recorded account like build runs do, including a personal project's owner", context do
      owner = AccountsFixtures.user_fixture(preload: [:account])
      personal_project = ProjectsFixtures.project_fixture(account_id: owner.account.id)
      by_owner = gradle_build(personal_project.id, owner.account.id)
      by_actor = gradle_build(personal_project.id, context.actor.account.id)

      assert BuildEntities.parent_actor_names(personal_project.id, :gradle, "task", [by_owner, by_actor]) ==
               %{by_owner => owner.account.name, by_actor => context.actor_name}

      # The default project belongs to an organization, which is never an actor.
      by_owner_organization = gradle_build(context.project.id, context.owner_account_id)
      assert BuildEntities.parent_actor_names(context.project.id, :gradle, "task", [by_owner_organization]) == %{}
    end

    test "maps Mix builds for files and modules", %{project: project, actor: actor, actor_name: actor_name} = context do
      ran = mix_build(project.id, actor.account.id)
      by_organization = mix_build(project.id, context.organization_account_id)

      for kind <- ["file", "module"] do
        assert BuildEntities.parent_actor_names(project.id, :mix, kind, [ran, by_organization]) == %{ran => actor_name}
      end
    end

    test "maps generate and cache commands for modules through the attributed user", context do
      %{project: project, actor: actor, actor_name: actor_name} = context
      ran = CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "generate", user_id: actor.id)
      by_token = CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "cache", user_id: nil)

      elsewhere =
        CommandEventsFixtures.command_event_fixture(
          project_id: context.other_project.id,
          name: "cache",
          user_id: actor.id
        )

      ids = [ran.id, by_token.id, elsewhere.id]
      assert BuildEntities.parent_actor_names(project.id, :xcode, "module", ids) == %{ran.id => actor_name}
    end

    test "uses the latest command version even when it cleared the attributed user", %{project: project, actor: actor} do
      cleared = CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "generate", user_id: actor.id)

      IngestRepo.query!(
        """
        INSERT INTO command_events (id, project_id, name, user_id, created_at, ran_at, updated_at)
        VALUES ({id:UUID}, {project_id:Int64}, 'generate', NULL, now64(6), now64(6), now64(6) + INTERVAL 1 DAY)
        """,
        %{id: cleared.id, project_id: project.id}
      )

      assert BuildEntities.parent_actor_names(project.id, :xcode, "module", [cleared.id]) == %{}
    end

    test "maps Once client run IDs, including non-UUID ones", %{project: project, actor: actor} = context do
      once_run(project.id, "local-run-7", actor.account.id)
      once_run(project.id, "ci-run", nil)
      once_run(project.id, "organization-run", context.organization_account_id)
      once_run(context.other_project.id, "elsewhere", actor.account.id)

      ids = ["local-run-7", "ci-run", "organization-run", "elsewhere", "missing", "", "with" <> <<0>>]

      assert BuildEntities.parent_actor_names(project.id, :once, "action", ids) ==
               %{"local-run-7" => context.actor_name}
    end

    test "returns nothing for unsupported system/kind pairs", %{project: project, actor: actor} do
      ran = gradle_build(project.id, actor.account.id)

      assert BuildEntities.parent_actor_names(project.id, :bazel, "cache_action", [ran, "invocation"]) == %{}
      assert BuildEntities.parent_actor_names(project.id, :xcode, "cache_action", [ran]) == %{}
      assert BuildEntities.parent_actor_names(project.id, :gradle, "file", [ran]) == %{}
      assert BuildEntities.parent_actor_names(project.id, :gradle, "task", []) == %{}
    end

    test "rejects more than one page of valid IDs and ignores malformed ones", %{project: project} do
      ids = for _ <- 1..101, do: UUIDv7.generate()

      assert_raise ArgumentError, fn -> BuildEntities.parent_actor_names(project.id, :gradle, "task", ids) end

      assert BuildEntities.parent_actor_names(project.id, :gradle, "task", Enum.map(1..150, &"build-#{&1}")) == %{}
    end

    test "runs under the entity read limits and raises QueryLimitError", %{project: project} do
      test_pid = self()

      stub(ClickHouseRepo, :query, fn _sql, _params, opts ->
        send(test_pid, {:actor_query, opts})
        {:error, %Ch.Error{code: 241, message: "Memory limit exceeded"}}
      end)

      assert_raise QueryLimitError, fn ->
        BuildEntities.parent_actor_names(project.id, :gradle, "task", [UUIDv7.generate()])
      end

      assert_received {:actor_query, opts}
      assert Keyword.fetch!(opts, :settings)[:max_memory_usage] == 256 * 1024 * 1024
      assert Keyword.fetch!(opts, :timeout) == 25_000
    end
  end

  describe "parent_contexts/4" do
    setup %{project: project} do
      actor = AccountsFixtures.user_fixture(preload: [:account])
      %{actor: actor, actor_name: actor.account.name, other_project: ProjectsFixtures.project_fixture(), project: project}
    end

    test "labels Gradle builds with the root project and tags", %{actor: actor} = context do
      %{project: project, actor_name: actor_name} = context

      named =
        GradleFixtures.build_fixture(
          project_id: project.id,
          account_id: actor.account.id,
          root_project_name: "app",
          custom_tags: ["nightly"]
        )

      unnamed = GradleFixtures.build_fixture(project_id: project.id, account_id: 0, root_project_name: "")

      elsewhere =
        GradleFixtures.build_fixture(project_id: context.other_project.id, root_project_name: "other")

      ids = [named, String.upcase(named), unnamed, elsewhere, UUIDv7.generate(), "not-a-uuid"]

      assert BuildEntities.parent_contexts(project.id, :gradle, "task", ids) == %{
               named => %{label: "app", tags: ["nightly"], ran_by_name: actor_name},
               String.upcase(named) => %{label: "app", tags: ["nightly"], ran_by_name: actor_name},
               unnamed => %{label: nil, tags: [], ran_by_name: nil}
             }
    end

    test "labels Xcode commands with the raw command name", %{project: project, actor: actor} = context do
      generate =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "generate",
          command_arguments: ["generate", "App", "--no-open"],
          user_id: actor.id
        )

      cache = CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "cache", user_id: nil)

      elsewhere =
        CommandEventsFixtures.command_event_fixture(
          project_id: context.other_project.id,
          name: "generate",
          user_id: actor.id
        )

      assert BuildEntities.parent_contexts(project.id, :xcode, "module", [generate.id, cache.id, elsewhere.id]) == %{
               generate.id => %{
                 label: "generate",
                 command_arguments: "generate App --no-open",
                 ran_by_name: context.actor_name
               },
               cache.id => %{label: "cache", command_arguments: nil, ran_by_name: nil}
             }
    end

    test "labels Mix builds with mix compile", %{project: project, actor: actor, actor_name: actor_name} = context do
      ran = mix_build(project.id, actor.account.id)
      elsewhere = mix_build(context.other_project.id, actor.account.id)

      for kind <- ["file", "module"] do
        assert BuildEntities.parent_contexts(project.id, :mix, kind, [ran, elsewhere, UUIDv7.generate()]) ==
                 %{ran => %{label: "mix compile", ran_by_name: actor_name}}
      end
    end

    test "labels Once runs with their command display", %{project: project, actor: actor} = context do
      {:ok, _} =
        OnceEvents.upsert_run(%{
          project_id: project.id,
          run_id: "local-run",
          account_id: actor.account.id,
          command_display: "once build //app"
        })

      once_run(project.id, "ci-run", nil)
      once_run(context.other_project.id, "elsewhere", actor.account.id)

      assert BuildEntities.parent_contexts(project.id, :once, "action", ["local-run", "ci-run", "elsewhere", "missing"]) ==
               %{
                 "local-run" => %{label: "once build //app", ran_by_name: context.actor_name},
                 "ci-run" => %{label: nil, ran_by_name: nil}
               }
    end

    test "the latest parent version decides, including one that cleared the label and actor", %{
      project: project,
      actor: actor
    } do
      command = CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "generate", user_id: actor.id)

      IngestRepo.query!(
        """
        INSERT INTO command_events (id, project_id, name, user_id, created_at, ran_at, updated_at)
        VALUES ({id:UUID}, {project_id:Int64}, '', NULL, now64(6), now64(6), now64(6) + INTERVAL 1 DAY)
        """,
        %{id: command.id, project_id: project.id}
      )

      assert BuildEntities.parent_contexts(project.id, :xcode, "module", [command.id]) ==
               %{command.id => %{label: nil, command_arguments: nil, ran_by_name: nil}}
    end

    test "bounds the page, rejects invalid pairs and enforces query limits", %{project: project} do
      assert BuildEntities.parent_contexts(project.id, :gradle, "file", [UUIDv7.generate()]) == %{}

      assert_raise ArgumentError, fn ->
        BuildEntities.parent_contexts(project.id, :once, "action", Enum.map(1..101, &"run-#{&1}"))
      end

      stub(ClickHouseRepo, :query, fn _sql, _params, _opts ->
        {:error, %Ch.Error{code: 159, message: "Timeout exceeded"}}
      end)

      assert_raise QueryLimitError, fn ->
        BuildEntities.parent_contexts(project.id, :xcode, "module", [UUIDv7.generate()])
      end

      # Unsupported pairs are never looked up, so no query can fail.
      assert BuildEntities.parent_contexts(project.id, :xcode, "cache_action", [UUIDv7.generate()]) == %{}
      assert BuildEntities.parent_actor_names(project.id, :bazel, "cache_action", ["invocation-1"]) == %{}
    end
  end

  defp gradle_build(project_id, account_id) do
    GradleFixtures.build_fixture(project_id: project_id, account_id: account_id)
  end

  defp mix_build(project_id, account_id, actor_attrs \\ %{}) do
    {:ok, id} =
      Mix.create_build(
        Map.merge(
          %{
            id: UUIDv7.generate(),
            project_id: project_id,
            account_id: account_id,
            duration_ms: 10,
            status: "success"
          },
          actor_attrs
        )
      )

    id
  end

  defp once_run(project_id, run_id, account_id) do
    {:ok, _run} = OnceEvents.upsert_run(%{project_id: project_id, run_id: run_id, account_id: account_id})
  end

  defp file_id(project, path), do: Identity.id(project.id, :mix, "file", %{"path" => path})
end
