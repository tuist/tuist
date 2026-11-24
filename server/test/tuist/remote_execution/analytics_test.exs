defmodule Tuist.RemoteExecution.AnalyticsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Bazel
  alias Tuist.Bazel.Profile
  alias Tuist.Bazel.ProfileSteps
  alias Tuist.RemoteExecution.Analytics
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "only current published profile evidence in the project, environment and half-open period contributes" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    other = ProjectsFixtures.project_fixture(build_system: :bazel)
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    opts = [since: NaiveDateTime.add(now, -3600), until: now, environment: "ci"]

    for {owner, id, ci?, finished} <- [
          {project, "shared", true, NaiveDateTime.add(now, -60)},
          {other, "shared", true, NaiveDateTime.add(now, -60)},
          {project, "local-run", false, NaiveDateTime.add(now, -60)},
          {project, "old", true, NaiveDateTime.add(now, -3601)},
          {project, "boundary", true, now},
          {project, "fetch-only", true, NaiveDateTime.add(now, -30)}
        ] do
      invocation(owner, id, ci?, finished)
      profile(owner, id, 999, 999)
    end

    # A re-reported invocation counts at its current finish time, not a superseded one.
    invocation(project, "moved", true, NaiveDateTime.add(now, -60))
    profile(project, "moved", 999, 999)
    invocation(project, "moved", true, NaiveDateTime.add(now, -7200))

    # Replacing a profile supersedes its earlier version instead of adding to it.
    profile(project, "shared", 0, 100)
    profile(project, "shared", 0, 100)
    profile(project, "fetch-only", nil, nil)

    # A newer unpublished step version must not supersede the published profile.
    ProfileSteps.insert(project, "shared", "pending", %{
      events: [
        %{
          event_id: "pending",
          title: "Pending",
          project: "",
          target: "",
          category: "",
          primary_output: "",
          start_ms: 0.0,
          duration_ms: 1.0,
          remote_queue_ms: 9000.0
        }
      ],
      profile_started_at_ms: 0
    })

    assert %{actions: 2, invocations: 2, queue: queue, execution: execution} = Analytics.summary(project.id, opts)

    # Fetch-only contributes no queue/execution sample, not a zero sample.
    assert queue.avg == 0
    assert execution.avg == 100
    assert_in_delta execution.p99, 100, 0.01

    assert %{rows: [%{invocation_id: "shared", execution_ms: 100.0, execution_p90_ms: 100.0}]} =
             Analytics.activity(project.id, Keyword.put(opts, :search, "SHARED"))

    assert %{rows: [%{execution_ms: nil, execution_p90_ms: nil}]} =
             Analytics.activity(project.id, Keyword.put(opts, :search, "fetch-only"))

    # Runs without measurements sort last in both directions.
    for order <- ~w(asc desc) do
      assert %{rows: [_, %{invocation_id: "fetch-only"}]} =
               Analytics.activity(project.id, opts ++ [sort_by: "execution-p90", sort_order: order])
    end

    assert %{actions: 1, invocations: 1, queue: %{avg: nil, p90: nil}, execution: %{avg: nil}} =
             Analytics.summary(project.id, Keyword.put(opts, :since, NaiveDateTime.add(now, -45)))

    assert %{actions: 1, execution: %{avg: 999.0}} =
             Analytics.summary(project.id, Keyword.put(opts, :environment, "local"))
  end

  test "percentiles summarize every recorded action across runs" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    for {id, execution} <- [{"a", 100}, {"b", 300}, {"c", 1100}] do
      invocation(project, id, true, NaiveDateTime.add(now, -60))
      profile(project, id, 10, execution)
    end

    assert %{invocations: 3, actions: 3, execution: execution} =
             Analytics.summary(project.id, since: NaiveDateTime.add(now, -3600), until: now)

    assert_in_delta execution.avg, 500, 0.01
    assert execution.p50 > 100 and execution.p50 < 1100
    assert execution.p99 > execution.p50

    # Each invocation row has its own percentiles over its actions.
    invocation(project, "multi", true, NaiveDateTime.add(now, -30))

    events =
      for {execution, tid} <- [{100, 1}, {300, 2}, {1100, 3}], event <- [:action, :execute] do
        if event == :action,
          do: %{ph: "X", pid: 1, tid: tid, cat: "action processing", name: "Compile #{tid}", ts: 0, dur: 2_000_000},
          else: %{
            ph: "X",
            pid: 1,
            tid: tid,
            cat: "Remote execution process wall time",
            name: "execute",
            ts: 1000,
            dur: execution * 1000
          }
      end

    assert :ok =
             Profile.ingest(
               project,
               "multi",
               :zlib.gzip(JSON.encode!(%{otherData: %{build_id: "multi"}, traceEvents: events}))
             )

    assert %{rows: [row]} =
             Analytics.activity(project.id, since: NaiveDateTime.add(now, -3600), until: now, search: "multi")

    assert row.actions == 3
    assert_in_delta row.execution_ms, 500, 0.01
    assert_in_delta row.execution_p50_ms, 300, 0.01
    assert_in_delta row.execution_p90_ms, 1100, 0.01
    refute Map.has_key?(row, :execution_p99_ms)

    sorted =
      Analytics.activity(project.id, since: NaiveDateTime.add(now, -3600), until: now, sort_by: "execution-p90").rows

    assert hd(sorted).invocation_id == "c"
  end

  test "activity filters before pagination with stable ordering" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    for index <- 1..23 do
      id = "run-#{String.pad_leading(to_string(index), 2, "0")}"
      invocation(project, id, true, NaiveDateTime.add(now, -index))
      profile(project, id, 0, index)
    end

    opts = [since: NaiveDateTime.add(now, -3600), until: now]
    assert %{rows: first, has_next_page?: true} = Analytics.activity(project.id, opts)
    assert length(first) == 20
    assert hd(first).invocation_id == "run-01"
    assert %{rows: last, has_next_page?: false} = Analytics.activity(project.id, Keyword.put(opts, :page, 2))
    assert Enum.map(last, & &1.invocation_id) == ~w(run-21 run-22 run-23)

    assert %{rows: [%{invocation_id: "run-23"}], has_next_page?: false} =
             Analytics.activity(project.id, Keyword.put(opts, :search, "run-23"))

    assert %{rows: rows} = Analytics.activity(project.id, Keyword.put(opts, :search, "//app:demo"))
    assert length(rows) == 20

    sorted = fn sort_by, order -> Analytics.activity(project.id, opts ++ [sort_by: sort_by, sort_order: order]).rows end
    assert hd(sorted.("execution", "desc")).invocation_id == "run-23"
    assert hd(sorted.("execution", "asc")).invocation_id == "run-01"
    assert hd(sorted.("ran-at", "asc")).invocation_id == "run-23"

    filtered = fn filters -> Analytics.activity(project.id, Keyword.put(opts, :filters, filters)) end
    assert %{rows: [], has_next_page?: false} = filtered.([%{field: :actions, op: :>=, value: "2"}])
    assert %{has_next_page?: true} = filtered.([%{field: :actions, op: :==, value: "1"}])
    assert %{rows: []} = filtered.([%{field: :status, op: :!=, value: "success"}])
    assert %{rows: []} = filtered.([%{field: :command, op: :not_ilike, value: "BUILD"}])

    combined = [%{field: :target_patterns, op: :=~, value: "DEMO"}, %{field: :command, op: :==, value: "build"}]
    assert %{has_next_page?: true} = filtered.(combined)

    assert %{rows: [%{invocation_id: "run-07"}]} =
             Analytics.activity(project.id, opts ++ [search: "run-07", filters: combined])
  end

  test "time series buckets keep empty days as gaps rather than zero-duration work" do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)
    # Midday keeps the bucket count independent of when the test runs.
    now = NaiveDateTime.new!(Date.utc_today(), ~T[12:00:00])

    for {id, seconds} <- [{"older", -3 * 86_400}, {"newer", -86_400}] do
      invocation(project, id, true, NaiveDateTime.add(now, seconds))
      profile(project, id, 0, 100)
    end

    series = Analytics.time_series(project.id, since: NaiveDateTime.add(now, -4 * 86_400), until: now)

    assert series.granularity == :day
    assert length(series.dates) == 5
    assert series.invocations == [0, 1, 0, 1, 0]
    assert series.queue.avg == [nil, 0, nil, 0, nil]
    assert series.execution.p90 |> Enum.reject(&is_nil/1) |> Enum.map(&round/1) == [100, 100]

    hourly = Analytics.time_series(project.id, since: NaiveDateTime.add(now, -86_400), until: now)
    assert hourly.granularity == :hour
  end

  defp invocation(project, id, ci?, finished) do
    Bazel.create_invocations([
      %{
        project_id: project.id,
        account_handle: "synthetic",
        project_handle: project.name,
        invocation_id: id,
        command: "build",
        target_patterns: ["//app:demo"],
        git_branch: "main",
        is_ci: ci?,
        status: "success",
        exit_code: 0,
        started_at: NaiveDateTime.add(finished, -1),
        finished_at: finished,
        duration_ms: 1000,
        cache_endpoint: "cache.example.test"
      }
    ])
  end

  defp profile(project, id, queue, execution) do
    phases =
      for {category, name, duration} <- [
            {"Remote execution queuing time", "queue", queue},
            {"Remote execution process wall time", "execute", execution},
            {"Remote execution file fetching", "fetch", 5}
          ],
          not is_nil(duration) do
        %{ph: "X", pid: 1, tid: 1, cat: category, name: name, ts: 1000, dur: duration * 1000}
      end

    events = [%{ph: "X", pid: 1, tid: 1, cat: "action processing", name: "Compile", ts: 0, dur: 2_000_000} | phases]
    assert :ok = Profile.ingest(project, id, :zlib.gzip(JSON.encode!(%{otherData: %{build_id: id}, traceEvents: events})))
  end
end
