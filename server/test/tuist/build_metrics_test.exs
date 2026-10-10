defmodule Tuist.BuildMetricsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Bazel
  alias Tuist.BuildMetrics
  alias Tuist.Builds
  alias Tuist.Builds.BuildIssue
  alias Tuist.Gradle
  alias Tuist.IngestRepo
  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Action
  alias Tuist.OnceEvents.Analytics
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup do
    start_at = DateTime.new!(Date.utc_today(), ~T[00:00:00.000000])
    %{start_at: start_at, opts: [start_datetime: start_at, end_datetime: DateTime.add(start_at, 1, :day)]}
  end

  defp listing("gradle", project, params), do: Gradle.list_builds(project.id, params, failure_category: true)

  defp listing("xcode", project, params), do: Builds.list_build_runs(params, failure_category_project_id: project.id)

  defp listing("bazel", project, params), do: Bazel.list_invocations(project.id, params, failure_category: true)

  defp listing("once", project, params), do: Analytics.list_invocations(project.id, params, failure_category: true)

  test "detail categories match listing classifications and remain project scoped", %{start_at: start_at} do
    for system <- ~w(gradle xcode bazel once) do
      project = ProjectsFixtures.project_fixture(build_system: String.to_existing_atom(system))
      other = ProjectsFixtures.project_fixture(build_system: String.to_existing_atom(system))

      build(system, project, start_at,
        status: "failure",
        exit_status: 1,
        exit_code: 1,
        failed_test_cases: 1,
        custom_values: %{"tuist.detected_failure_category" => "verification"}
      )

      build(system, project, DateTime.add(start_at, 1), status: "success", exit_status: 0)
      {rows, _} = listing(system, project, %{filters: [%{field: :project_id, op: :==, value: project.id}], page_size: 10})
      assert length(rows) == 2

      for row <- rows do
        id =
          case system do
            "bazel" -> row.invocation_id
            "once" -> row.invocation_id
            _ -> row.id
          end

        assert BuildMetrics.failure_category(project.id, system, id) ==
                 if(row.failure_category == "", do: nil, else: row.failure_category)

        assert BuildMetrics.failure_category(other.id, system, id) == nil
      end
    end
  end

  test "native category sorting and filtering cover the full cohort before pagination", %{start_at: start_at} do
    for system <- ~w(gradle xcode bazel once) do
      project = ProjectsFixtures.project_fixture(build_system: String.to_existing_atom(system))
      other = ProjectsFixtures.project_fixture(build_system: String.to_existing_atom(system))

      for i <- 1..23 do
        build(system, project, DateTime.add(start_at, i), status: "failure", exit_status: 1, exit_code: 1)
      end

      attrs = [
        status: "failure",
        exit_status: 1,
        exit_code: 1,
        failed_test_cases: 1,
        custom_values: %{"tuist.detected_failure_category" => "verification"}
      ]

      build(system, project, start_at, attrs)
      build(system, other, start_at, attrs)

      build(system, project, DateTime.add(start_at, 30),
        status: "success",
        exit_status: 0,
        custom_values: %{"tuist.failure_category" => "verification"}
      )

      filters = [%{field: :project_id, op: :==, value: project.id}]
      params = %{filters: filters, order_by: [:failure_category], order_directions: [:desc], page: 1, page_size: 2}
      {rows, _} = listing(system, project, params)
      assert Enum.map(rows, & &1.failure_category) == ["verification", "unknown"]

      {rows, meta} =
        listing(system, project, %{
          params
          | filters: filters ++ [%{field: :failure_category, op: :==, value: "verification"}]
        })

      assert length(rows) == 1
      assert meta.total_count == 1

      {rows, meta} =
        listing(system, project, %{
          params
          | filters: filters ++ [%{field: :failure_category, op: :!=, value: "verification"}]
        })

      assert meta.total_count == 24
      refute Enum.any?(rows, &(&1.failure_category == "verification"))
      {rows, _} = listing(system, project, %{params | order_directions: [:asc]})
      assert hd(rows).failure_category == ""
    end
  end

  test "Xcode category cursors preserve tied builds without duplication", %{start_at: start_at} do
    project = ProjectsFixtures.project_fixture()
    for _ <- 1..5, do: build("xcode", project, start_at, status: "failure")

    params = %{
      first: 2,
      filters: [%{field: :project_id, op: :==, value: project.id}],
      order_by: [:failure_category, :inserted_at, :id],
      order_directions: [:asc, :asc, :asc]
    }

    {first, meta} = listing("xcode", project, params)
    {second, meta} = listing("xcode", project, Map.put(params, :after, meta.end_cursor))
    {third, _} = listing("xcode", project, Map.put(params, :after, meta.end_cursor))
    assert length(Enum.uniq_by(first ++ second ++ third, & &1.id)) == 5
  end

  defp build("gradle", project, start_at, attrs) do
    GradleFixtures.build_fixture(
      Keyword.merge(
        [project_id: project.id, inserted_at: start_at |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)],
        attrs
      )
    )
  end

  defp build("xcode", project, start_at, attrs) do
    RunsFixtures.build_fixture(
      Keyword.merge(
        [project_id: project.id, inserted_at: DateTime.to_naive(start_at), duration: 1000, git_branch: "main"],
        attrs
      )
    )
  end

  defp build("bazel", project, start_at, attrs) do
    defaults = %{
      invocation_id: UUIDv7.generate(),
      command: "build",
      target_patterns: ["//app:app"],
      status: "success",
      exit_code: 0,
      started_at: DateTime.to_naive(DateTime.truncate(start_at, :second)),
      finished_at: DateTime.to_naive(DateTime.truncate(DateTime.add(start_at, 1), :second)),
      duration_ms: 1000,
      project_id: project.id,
      account_handle: project.account.name,
      project_handle: project.name,
      cache_endpoint: "",
      git_branch: "main"
    }

    Bazel.create_invocations([Map.merge(defaults, Map.new(attrs))])
  end

  defp build("once", project, start_at, attrs) do
    attrs = Map.new(attrs)

    {:ok, run} =
      OnceEvents.upsert_run(%{
        project_id: project.id,
        run_id: UUIDv7.generate(),
        kind: Map.get(attrs, :kind, "build"),
        started_at: start_at,
        git_branch: Map.get(attrs, :git_branch, "main"),
        is_ci: Map.get(attrs, :is_ci, false),
        failed_test_cases: Map.get(attrs, :failed_test_cases, 0)
      })

    {:ok, run} = OnceEvents.finalize_run(run, Map.merge(%{exit_status: 0, wall_ms: 1000}, attrs))
    run
  end

  test "Bazel infrastructure exit codes win over detected verification but not explicit overrides", %{
    start_at: start_at,
    opts: opts
  } do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)

    build("bazel", project, start_at,
      status: "failure",
      exit_code: 37,
      custom_values: %{"tuist.detected_failure_category" => "verification"}
    )

    build("bazel", project, start_at,
      status: "failure",
      exit_code: 37,
      custom_values: %{"tuist.failure_category" => "verification"}
    )

    result = BuildMetrics.query(project.id, Keyword.merge(opts, build_system: "bazel", view: "failures"))

    assert result.rows == [
             %{category: "verification", builds: 1},
             %{category: "infrastructure_tooling", builds: 1},
             %{category: "unknown", builds: 0}
           ]
  end

  test "dimension lookups bound generic history while retaining configurable legacy behavior", %{start_at: start_at} do
    project = ProjectsFixtures.project_fixture(build_system: :xcode)
    build("xcode", project, DateTime.add(start_at, -2, :day), git_branch: "old")
    build("xcode", project, DateTime.truncate(DateTime.utc_now(), :second), git_branch: "recent")
    assert BuildMetrics.dimension_values(project.id, "git_branch", "xcode", lookback_days: 1) == ["recent"]
    assert BuildMetrics.dimension_values(project.id, "git_branch", "xcode", lookback_days: nil) == ["old", "recent"]
  end

  for system <- ["xcode", "bazel", "once"] do
    test "#{system} supports totals, buckets, workloads, failure categories and links", %{start_at: start_at, opts: opts} do
      system = unquote(system)
      project = ProjectsFixtures.project_fixture(build_system: String.to_existing_atom(system))
      build(system, project, start_at, [])

      failure_attrs =
        case system do
          "xcode" ->
            [status: "failure", duration: 3000, custom_values: %{"tuist.failure_category" => "verification"}]

          "bazel" ->
            [
              status: "failure",
              exit_code: 1,
              duration_ms: 3000,
              custom_values: %{"tuist.failure_category" => "verification"}
            ]

          "once" ->
            [exit_status: 1, wall_ms: 3000, failed_test_cases: 1]
        end

      build(system, project, start_at, failure_attrs)
      other = ProjectsFixtures.project_fixture(build_system: String.to_existing_atom(system))
      build(system, other, start_at, failure_attrs)
      opts = Keyword.merge(opts, build_system: system, slow_build_threshold_ms: 2000)
      result = BuildMetrics.query(project.id, opts)
      assert result.totals["cache_work_avoided"] == nil
      assert result.totals["cache_work_avoided_samples"] == 0
      assert result.totals["builds"] == 2
      assert result.totals["success_rate"] == 50
      assert result.totals["p50"] == 2000
      assert result.totals["builds_needing_attention"] == 1
      assert result.totals["cache_time_saved"] == nil
      assert Enum.sum(result.series["builds"]) == 2
      assert List.last(result.series["p50"]) == nil
      assert [%{"builds" => 2}] = BuildMetrics.query(project.id, Keyword.put(opts, :view, "workloads")).rows

      assert %{category: "verification", builds: 1} in BuildMetrics.query(
               project.id,
               Keyword.put(opts, :view, "failures")
             ).rows

      assert [failure] = BuildMetrics.query(project.id, Keyword.put(opts, :view, "recent_failures")).rows
      assert failure.build_system == system
      assert failure.duration_ms == 3000
      assert failure.git_branch == "main"
      assert BuildMetrics.dimension_values(project.id, "git_branch", system) == ["main"]
      filtered = Keyword.put(opts, :git_branch, "other")
      assert BuildMetrics.query(project.id, filtered).totals["builds"] == 0
      assert BuildMetrics.query(project.id, Keyword.put(filtered, :view, "recent_failures")).rows == []
    end
  end

  test "Once cancellations do not count as failures and active or abandoned runs are excluded", %{
    start_at: start_at,
    opts: opts
  } do
    project = ProjectsFixtures.project_fixture(build_system: :once)
    build("once", project, start_at, [])
    build("once", project, start_at, exit_status: 1, cancellation_reason: "user interrupted")
    build("once", project, start_at, finalization: "active")
    build("once", project, start_at, finalization: "lost", exit_status: nil)
    opts = Keyword.put(opts, :build_system, "once")
    result = BuildMetrics.query(project.id, opts)
    assert result.totals["builds"] == 2
    assert result.totals["cancelled_builds"] == 1
    assert result.totals["failed_builds"] == 0
    assert result.totals["success_rate"] == 100
    assert result.totals["slow_build_threshold"] == 1000
  end

  test "Once infrastructure failure uses recorded action evidence", %{start_at: start_at, opts: opts} do
    project = ProjectsFixtures.project_fixture(build_system: :once)
    run = build("once", project, start_at, exit_status: 1)

    Repo.insert!(%Action{
      once_run_id: run.id,
      run_id: run.run_id,
      project_id: project.id,
      target_execution_id: "app",
      capability: "build",
      identifier: "compiler",
      result: "infrastructure_error",
      started_at: start_at,
      finished_at: DateTime.add(start_at, 1)
    })

    result = BuildMetrics.query(project.id, Keyword.merge(opts, build_system: "once", view: "failures"))
    assert %{category: "infrastructure_tooling", builds: 1} in result.rows

    assert [failure] =
             BuildMetrics.query(project.id, Keyword.merge(opts, build_system: "once", view: "recent_failures")).rows

    assert failure.id == run.run_id
  end

  test "Bazel interruptions are cancelled and queries are excluded", %{start_at: start_at, opts: opts} do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    build("bazel", project, start_at, [])
    build("bazel", project, start_at, status: "failure", exit_code: 8)
    build("bazel", project, start_at, command: "query")
    result = BuildMetrics.query(project.id, Keyword.put(opts, :build_system, "bazel"))
    assert result.totals["builds"] == 2
    assert result.totals["cancelled_builds"] == 1
    assert result.totals["success_rate"] == 100
  end

  test "Xcode processing placeholders are excluded and metadata is used", %{start_at: start_at, opts: opts} do
    project = ProjectsFixtures.project_fixture()
    build("xcode", project, start_at, status: "processing")
    build("xcode", project, start_at, status: "failed_processing")

    build("xcode", project, start_at,
      custom_values: %{"tuist.workload" => "Release", "tuist.cache_time_saved_ms" => "12000"}
    )

    result = BuildMetrics.query(project.id, Keyword.merge(opts, build_system: "xcode", workload: "Release"))
    assert result.totals["builds"] == 1
    assert result.totals["cache_time_saved"] == 12_000
    assert result.totals["cache_time_saved_samples"] == 1
  end

  test "Bazel uses documented failures, metadata and public invocation identifiers", %{start_at: start_at, opts: opts} do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    build("bazel", project, start_at, status: "failure", exit_code: 3, command: "test", invocation_id: "failed-tests")
    build("bazel", project, start_at, status: "failure", exit_code: 33)
    build("bazel", project, start_at, status: "failure", exit_code: 8, command: "run")

    build("bazel", project, start_at,
      custom_values: %{"tuist.cache_time_saved_ms" => "1234", "tuist.workload" => "Release"}
    )

    opts = Keyword.put(opts, :build_system, "bazel")
    totals = BuildMetrics.query(project.id, opts).totals
    assert totals["cache_time_saved"] == 1234
    assert totals["cache_time_saved_samples"] == 1
    assert totals["cancelled_builds"] == 0
    rows = BuildMetrics.query(project.id, Keyword.put(opts, :view, "failures")).rows
    assert %{category: "verification", builds: 1} in rows
    assert %{category: "infrastructure_tooling", builds: 1} in rows
    assert %{category: "unknown", builds: 1} in rows
    rows = BuildMetrics.query(project.id, Keyword.put(opts, :view, "recent_failures")).rows
    assert Enum.any?(rows, &(&1.id == "failed-tests"))
    assert "Release" in BuildMetrics.dimension_values(project.id, "workload", "bazel")
  end

  test "Once ranges exclude their end and retain missing duration", %{start_at: start_at, opts: opts} do
    project = ProjectsFixtures.project_fixture(build_system: :once)
    build("once", project, start_at, exit_status: 1, wall_ms: nil)
    build("once", project, opts[:end_datetime], [])
    opts = Keyword.put(opts, :build_system, "once")
    totals = BuildMetrics.query(project.id, opts).totals
    assert totals["builds"] == 1
    assert totals["average"] == nil
    assert totals["p50"] == nil
    assert totals["builds_needing_attention"] == 1
    assert [row] = BuildMetrics.query(project.id, Keyword.put(opts, :view, "recent_failures")).rows
    assert row.duration_ms == nil
  end

  test "Xcode compiler issues classify historical failures without metadata and exclude other projects", %{
    start_at: start_at,
    opts: opts
  } do
    project = ProjectsFixtures.project_fixture()
    {:ok, failed} = build("xcode", project, start_at, status: "failure")
    other = ProjectsFixtures.project_fixture()
    {:ok, unrelated} = build("xcode", other, start_at, status: "failure")

    for run <- [failed, unrelated] do
      IngestRepo.insert!(%BuildIssue{
        build_run_id: run.id,
        type: "error",
        step_type: "swift_compilation",
        target: "App",
        project: "App",
        title: "Cannot find value",
        signature: "error",
        path: "App.swift",
        message: "Cannot find value in scope",
        starting_line: 1,
        ending_line: 1,
        starting_column: 1,
        ending_column: 1,
        inserted_at: start_at |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)
      })
    end

    rows =
      BuildMetrics.query(
        project.id,
        Keyword.merge(opts, build_system: "xcode", view: "failures", include_failure_total: true)
      ).rows

    assert %{category: "verification", builds: 1} in rows
    assert %{category: "all", builds: 1} in rows

    {[native], _} =
      listing("xcode", project, %{
        filters: [
          %{field: :project_id, op: :==, value: project.id},
          %{field: :failure_category, op: :==, value: "verification"}
        ],
        first: 20,
        order_by: [:inserted_at],
        order_directions: [:desc]
      })

    assert native.id == failed.id

    assert Enum.sum(for row <- rows, row.category != "all", do: row.builds) == 1
  end

  test "Once infrastructure evidence takes precedence over tests and unknown commands remain unknown", %{
    start_at: start_at,
    opts: opts
  } do
    project = ProjectsFixtures.project_fixture(build_system: :once)
    run = build("once", project, start_at, exit_status: 1, failed_test_cases: 1)

    Repo.insert!(%Action{
      once_run_id: run.id,
      run_id: run.run_id,
      project_id: project.id,
      target_execution_id: "app",
      capability: "build",
      identifier: "compiler",
      result: "infrastructure_error",
      started_at: start_at,
      finished_at: DateTime.add(start_at, 1)
    })

    build("once", project, start_at, exit_status: 1)
    rows = BuildMetrics.query(project.id, Keyword.merge(opts, build_system: "once", view: "failures")).rows
    assert %{category: "infrastructure_tooling", builds: 1} in rows
    assert %{category: "unknown", builds: 1} in rows
    assert %{category: "verification", builds: 0} in rows
  end

  test "detected categories distinguish compiler failures from infrastructure and explicit overrides win", %{
    start_at: start_at,
    opts: opts
  } do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)

    build("bazel", project, start_at,
      status: "failure",
      exit_code: 1,
      custom_values: %{"tuist.detected_failure_category" => "verification"}
    )

    build("bazel", project, start_at,
      status: "failure",
      exit_code: 1,
      custom_values: %{"tuist.detected_failure_category" => "infrastructure_tooling"}
    )

    build("bazel", project, start_at,
      status: "failure",
      exit_code: 34,
      custom_values: %{
        "tuist.failure_category" => "verification",
        "tuist.detected_failure_category" => "infrastructure_tooling"
      }
    )

    rows = BuildMetrics.query(project.id, Keyword.merge(opts, build_system: "bazel", view: "failures")).rows
    assert %{category: "verification", builds: 2} in rows
    assert %{category: "infrastructure_tooling", builds: 1} in rows
  end

  for system <- ["xcode", "once"] do
    test "#{system} generic partial buckets stay visible and legacy timestamps remain unchanged", %{start_at: start_at} do
      system = unquote(system)
      project = ProjectsFixtures.project_fixture(build_system: String.to_existing_atom(system))
      start_at = DateTime.add(start_at, 7 * 60 + 13)
      build(system, project, start_at, [])
      opts = [build_system: system, start_datetime: start_at, end_datetime: DateTime.add(start_at, 15, :minute)]
      original = BuildMetrics.query(project.id, opts)
      visible = BuildMetrics.query(project.id, Keyword.put(opts, :clip_series_start, true))
      assert visible.dates == [DateTime.to_unix(start_at)]
      assert visible.series == original.series
      assert visible.series["builds"] == [1]
      assert hd(original.dates) < hd(visible.dates)
    end
  end

  test "native overview dimensions filter categories and linked failures", %{start_at: start_at, opts: opts} do
    project = ProjectsFixtures.project_fixture(build_system: :xcode)

    build("xcode", project, start_at,
      status: "failure",
      scheme: "App",
      configuration: "Debug",
      category: "clean",
      custom_tags: ["release"],
      custom_values: %{"tuist.detected_failure_category" => "verification"}
    )

    build("xcode", project, start_at,
      status: "failure",
      scheme: "Other",
      configuration: "Release",
      category: "incremental",
      custom_values: %{"tuist.detected_failure_category" => "infrastructure_tooling"}
    )

    opts =
      Keyword.merge(opts, build_system: "xcode", scheme: "App", configuration: "Debug", category: "clean", tag: "release")

    assert %{rows: [%{category: "verification", builds: 1}, %{builds: 0}, %{builds: 0}]} =
             BuildMetrics.query(project.id, Keyword.put(opts, :view, "failures"))

    assert %{rows: [%{requested_tasks: ["App"]}]} =
             BuildMetrics.query(project.id, Keyword.put(opts, :view, "recent_failures"))

    assert %{rows: []} = BuildMetrics.query(project.id, Keyword.merge(opts, view: "recent_failures", tag: "missing"))
  end

  test "Bazel and Once build overviews exclude test invocations", %{start_at: start_at, opts: opts} do
    for system <- ["bazel", "once"] do
      project = ProjectsFixtures.project_fixture(build_system: String.to_existing_atom(system))

      {key, attrs} =
        if system == "bazel", do: {:command, [status: "failure", exit_code: 1]}, else: {:kind, [exit_status: 1]}

      build(system, project, start_at, Keyword.put(attrs, key, "build"))
      build(system, project, start_at, Keyword.put(attrs, key, "test"))

      result =
        BuildMetrics.query(
          project.id,
          Keyword.merge(opts, [{:build_system, system}, {:view, "failures"}, {key, "build"}])
        )

      assert Enum.sum(Enum.map(result.rows, & &1.builds)) == 1
    end
  end

  test "native Gradle cache estimates reject invalid metadata and retain recorded zero" do
    for invalid <- [nil, "-1", "1.5", "abc", "31536000001", "000000000000"] do
      assert is_nil(BuildMetrics.cache_work_avoided(%{custom_values: %{"tuist.cache_work_avoided_ms" => invalid}}))
    end

    assert BuildMetrics.cache_work_avoided(%{custom_values: %{}}) == nil
    assert BuildMetrics.cache_work_avoided(%{custom_values: %{"tuist.cache_work_avoided_ms" => "0"}}) == 0
    assert BuildMetrics.cache_work_avoided(%{custom_values: %{"tuist.cache_work_avoided_ms" => "151"}}) == 151
  end

  test "Bazel build commands use collected compiler verification evidence", %{start_at: start_at, opts: opts} do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)

    build("bazel", project, start_at,
      command: "build",
      status: "failure",
      exit_code: 1,
      custom_values: %{"tuist.detected_failure_category" => "verification"}
    )

    assert %{rows: [%{category: "verification", builds: 1}, %{builds: 0}, %{builds: 0}]} =
             BuildMetrics.query(
               project.id,
               Keyword.merge(opts, build_system: "bazel", command: "build", view: "failures")
             )
  end
end
