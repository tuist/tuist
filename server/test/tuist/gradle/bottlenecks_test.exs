defmodule Tuist.Gradle.BottlenecksTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Gradle.Bottlenecks
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    project = ProjectsFixtures.project_fixture()
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    %{project: project, account: account}
  end

  test "rankings distinguish remote misses, cache-disabled execution and up-to-date work", %{
    project: project,
    account: account
  } do
    build(project, account, [task(":app:compileJava", "executed", 100, true)])
    build(project, account, [task(":app:compileJava", "remote_hit", 10, false)])
    build(project, account, [task(":app:compileJava", "executed", 300, false)])
    build(project, account, [task(":app:compileJava", "up_to_date", 5, false)])

    %{rows: [row]} = Bottlenecks.list(project.id)
    assert row.executions == 2
    assert row.misses == 1
    assert row.hit_rate == 50.0
    assert row.cumulative_duration_ms == 400
    assert row.p50_duration_ms == 200
    assert row.p90_duration_ms == 280
    assert row.p99_duration_ms == 298
  end

  test "cohort filters and project isolation apply to rankings and build history", %{project: project, account: account} do
    build(project, account, [task(":app:compileJava", "executed", 100, true)],
      is_ci: true,
      git_branch: "main",
      requested_tasks: [":app:jar"]
    )

    build(project, account, [task(":app:compileJava", "executed", 900, true)], is_ci: false, git_branch: "feature")
    other = ProjectsFixtures.project_fixture()
    build(other, account, [task(":app:compileJava", "executed", 9000, true)])
    opts = [is_ci: true, git_branch: "main", requested_task: ":app:jar"]
    assert %{rows: [%{cumulative_duration_ms: 100}]} = Bottlenecks.list(project.id, opts)
    assert %{rows: [%{duration_ms: 100}]} = Bottlenecks.task_executions(project.id, ":app:compileJava", opts)
  end

  test "a cacheable task without remote lookups has a zero hit rate and no execution percentiles", %{
    project: project,
    account: account
  } do
    build(project, account, [task(":app:compileJava", "local_hit", 10, false)])
    %{rows: [row]} = Bottlenecks.list(project.id)
    assert row.hit_rate == 0.0
    assert row.p50_duration_ms == nil
    assert row.p90_duration_ms == nil
    assert row.p99_duration_ms == nil
  end

  test "time series fill missing intervals and count identities across the whole period", %{
    project: project,
    account: account
  } do
    end_at = DateTime.new!(Date.utc_today(), ~T[00:00:00])
    start_at = DateTime.add(end_at, -3, :day)
    at = fn days -> start_at |> DateTime.add(days, :day) |> DateTime.to_naive() end

    build(project, account, [task(":app:compileJava", "executed", 100, true)],
      inserted_at: at.(0),
      root_project_name: "app"
    )

    build(project, account, [task(":app:compileJava", "remote_hit", 50, false)],
      inserted_at: at.(2),
      root_project_name: "app"
    )

    build(project, account, [task(":app:compileJava", "executed", 300, false)],
      inserted_at: at.(2),
      root_project_name: "other"
    )

    build(project, account, [task(":app:compileJava", "executed", 200, true)],
      inserted_at: at.(-1),
      root_project_name: "app"
    )

    other = ProjectsFixtures.project_fixture()
    build(other, account, [task(":app:compileJava", "executed", 9999, true)], inserted_at: at.(0))

    analytics = Bottlenecks.analytics(project.id, start_datetime: start_at, end_datetime: end_at)

    assert analytics.total == %{
             tasks: 2,
             builds: 3,
             executions: 2,
             hits: 1,
             hit_rate: 50.0,
             cacheability: :cacheable,
             misses: 1,
             cumulative_duration_ms: 400,
             avg_duration_ms: 200,
             p50_duration_ms: 200,
             p90_duration_ms: 280,
             p99_duration_ms: 298
           }

    assert analytics.previous == %{
             tasks: 1,
             builds: 1,
             executions: 1,
             hits: 0,
             hit_rate: 0.0,
             cacheability: :cacheable,
             misses: 1,
             cumulative_duration_ms: 200,
             avg_duration_ms: 200,
             p50_duration_ms: 200,
             p90_duration_ms: 200,
             p99_duration_ms: 200
           }

    assert Enum.map(analytics.points, & &1.hit_rate) == [0.0, nil, 100.0, nil]
    assert Enum.map(analytics.points, & &1.hits) == [0, 0, 1, 0]
    assert Enum.map(analytics.points, & &1.tasks) == [1, 0, 2, 0]
    assert Enum.map(analytics.points, & &1.cumulative_duration_ms) == [100, 0, 300, 0]

    detail =
      Bottlenecks.analytics(project.id,
        start_datetime: start_at,
        end_datetime: end_at,
        root_project_name: "app",
        build_path: ":",
        task_path: ":app:compileJava",
        task_type: "JavaCompile"
      )

    assert detail.total.tasks == 1
    assert detail.total.builds == 2
    assert detail.total.cumulative_duration_ms == 100
  end

  test "dropdown operators apply consistently to totals, charts, task executions", %{
    project: project,
    account: account
  } do
    matching =
      build(project, account, [task(":app:compileJava", "executed", 100, true)],
        git_branch: "release/main",
        requested_tasks: [":app:jar"],
        is_ci: true,
        gradle_version: "9.2.1",
        java_version: "21.0.2",
        telemetry_version: 1
      )

    build(project, account, [task(":app:compileJava", "executed", 900, true)],
      git_branch: "feature",
      requested_tasks: [":app:test"],
      is_ci: false,
      telemetry_version: 1
    )

    opts = [
      filters: [
        %{field: :git_branch, op: :=~, value: "MAIN"},
        %{field: :requested_tasks, op: :not_ilike, value: ":app:test"},
        %{field: :is_ci, op: :!=, value: :local},
        %{field: :gradle_version, op: :==, value: "9.2.1"},
        %{field: :java_version, op: :not_ilike, value: "17"}
      ]
    ]

    assert %{rows: [%{cumulative_duration_ms: 100}]} = Bottlenecks.list(project.id, opts)
    assert %{rows: [%{build_id: ^matching}]} = Bottlenecks.task_executions(project.id, ":app:compileJava", opts)
    analytics = Bottlenecks.analytics(project.id, opts)
    assert analytics.total.cumulative_duration_ms == 100
    assert Enum.sum(Enum.map(analytics.points, & &1.cumulative_duration_ms)) == 100

    empty = Bottlenecks.analytics(project.id, filters: [%{field: :git_branch, op: :==, value: "missing"}])
    assert empty.total.builds == 0
    assert Enum.all?(empty.points, &(&1.cumulative_duration_ms == 0))
  end

  test "short periods use hourly buckets and retain observed zero execution time", %{project: project, account: account} do
    end_at = DateTime.new!(Date.utc_today(), ~T[00:00:00])
    start_at = DateTime.add(end_at, -2, :hour)
    build(project, account, [task(":app:compileJava", "remote_hit", 50, false)], inserted_at: DateTime.to_naive(start_at))
    analytics = Bottlenecks.analytics(project.id, start_datetime: start_at, end_datetime: end_at)
    assert analytics.period == :hour
    assert Enum.map(analytics.points, & &1.tasks) == [1, 0, 0]
    assert analytics.total.builds == 1
    assert analytics.total.cumulative_duration_ms == 0
    assert analytics.total.avg_duration_ms == nil
    assert analytics.total.p90_duration_ms == nil
    assert analytics.previous.p90_duration_ms == nil
  end

  test "duration time series calculate execution percentiles and leave unsampled buckets empty", %{
    project: project,
    account: account
  } do
    end_at = DateTime.new!(Date.utc_today(), ~T[00:00:00])
    start_at = DateTime.add(end_at, -2, :hour)
    build(project, account, [task(":app:compile", "remote_hit", 9000, false)], inserted_at: DateTime.to_naive(start_at))

    for duration <- [100, 300, 500] do
      build(project, account, [task(":app:compile", "executed", duration, false)],
        inserted_at: start_at |> DateTime.add(1, :hour) |> DateTime.to_naive()
      )
    end

    analytics = Bottlenecks.analytics(project.id, start_datetime: start_at, end_datetime: end_at)
    assert [cached, executed, empty] = analytics.points

    for point <- [cached, empty] do
      assert point.avg_duration_ms == nil
      assert point.p50_duration_ms == nil
      assert point.p90_duration_ms == nil
      assert point.p99_duration_ms == nil
    end

    assert executed.avg_duration_ms == 300
    assert executed.cumulative_duration_ms == 900
    assert executed.p50_duration_ms == 300
    assert executed.p90_duration_ms == 460
    assert executed.p99_duration_ms == 496
  end

  test "cacheability distinguishes disabled, unknown, legacy and mixed observations", %{
    project: project,
    account: account
  } do
    disabled =
      ":app:disabled"
      |> task("executed", 100, false)
      |> Map.put(:cacheable, true)
      |> put_in([:execution, :cacheability], "disabled")

    unknown = put_in(task(":app:unknown", "executed", 100, false), [:execution, :cacheability], "unknown")
    mixed_disabled = %{disabled | task_path: ":app:mixed"}
    mixed_cacheable = task(":app:mixed", "local_hit", 5, false)
    build(project, account, [disabled, unknown, mixed_disabled], telemetry_version: 1)
    build(project, account, [mixed_cacheable], telemetry_version: 1)
    build(project, account, [%{task_path: ":app:legacy", outcome: "executed", duration_ms: 100, cacheable: false}])

    rows = Map.new(Bottlenecks.list(project.id).rows, &{&1.name, &1})
    assert rows[":app:disabled"].hit_rate == nil
    assert rows[":app:unknown"].hit_rate == nil
    assert rows[":app:disabled"].cacheability == :not_cacheable
    assert rows[":app:unknown"].cacheability == :unknown
    assert rows[":app:legacy"].cacheability == :not_cacheable
    assert rows[":app:mixed"].cacheability == :cacheable
    assert rows[":app:mixed"].hit_rate == 0.0
  end

  test "task executions paginate individual attempts and scope search and sorting", %{project: project, account: account} do
    for duration <- 1..27 do
      build(project, account, [task(":app:compile", "executed", duration, false)],
        root_project_name: "android",
        git_branch: "main",
        requested_tasks: [":app:assemble"]
      )
    end

    build(project, account, [task(":app:compile", "remote_hit", 500, false)],
      root_project_name: "android",
      git_branch: "feature",
      requested_tasks: [":app:test"]
    )

    build(project, account, [task(":app:compile", "executed", 999, false)], root_project_name: "other")

    opts = [root_project_name: "android", execution_sort: "duration", execution_order: "asc"]
    first = Bottlenecks.task_executions(project.id, ":app:compile", opts)
    second = Bottlenecks.task_executions(project.id, ":app:compile", Keyword.put(opts, :execution_page, 2))
    assert first.total_pages == 2
    assert Enum.map(first.rows, & &1.duration_ms) == Enum.to_list(1..25)
    assert Enum.map(second.rows, & &1.duration_ms) == [26, 27, 500]
    assert List.last(second.rows).outcome == "remote_hit"
    assert length(Enum.uniq_by(first.rows ++ second.rows, & &1.id)) == 28

    matching =
      Bottlenecks.task_executions(
        project.id,
        ":app:compile",
        Keyword.merge(opts, execution_search: ":APP:TEST", execution_page: 9)
      )

    assert matching.page == 1
    assert [%{duration_ms: 500, git_branch: "feature"}] = matching.rows

    empty = Bottlenecks.task_executions(project.id, ":app:compile", Keyword.put(opts, :execution_search, "missing"))
    assert empty.rows == []
    assert empty.total_pages == 1
  end

  defp build(project, account, tasks, opts \\ []) do
    GradleFixtures.build_fixture(Keyword.merge([project_id: project.id, account_id: account.id, tasks: tasks], opts))
  end

  defp task(path, outcome, duration, miss) do
    %{
      task_path: path,
      outcome: outcome,
      duration_ms: duration,
      remote_cache_miss: miss,
      execution: %{build_path: ":", project_path: ":app", task_type: "JavaCompile", cacheability: "cacheable"}
    }
  end
end
