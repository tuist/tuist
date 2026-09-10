defmodule Tuist.Builds.ModuleCacheQueryTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Builds.Analytics
  alias Tuist.ClickHouseRepo
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures

  setup do
    stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
    %{project: ProjectsFixtures.project_fixture()}
  end

  test "batches independent names while retaining the full window and event filters", %{project: project} do
    names = Enum.map(1..257, &"Module#{String.pad_leading(Integer.to_string(&1), 3, "0")}")

    expect(ClickHouseRepo, :query!, 3, fn query, params ->
      assert params.project_id == project.id
      assert params.start == ~U[2024-04-01 00:00:00Z]
      assert params.end == ~U[2024-04-30 23:59:59Z]

      case params do
        %{names: batch} ->
          assert length(batch) <= 256
          assert query =~ "PARTITION BY name, product, branch"
          assert query =~ "toLowCardinality(xt.name) AS name"
          assert query =~ "toLowCardinality(coalesce(e.git_branch, '')) AS branch"
          assert query =~ "xt.name IN {names:Array(String)}"
          assert query =~ "e.is_ci = true"
          assert query =~ "e.git_branch = {branch:String}"
          assert params.branch == "main"
          send(self(), {:batch, batch})
          %{rows: Enum.map(batch, &[~D[2024-04-02], &1, "framework", 3, 2, 1, 0])}

        _ ->
          assert query =~ "GROUP BY xt.name"
          refute query =~ "SELECT DISTINCT"
          %{rows: Enum.map(names, &[&1])}
      end
    end)

    breakdown =
      Analytics.module_invalidation_breakdown(
        project_id: project.id,
        start_datetime: ~U[2024-04-01 00:00:00Z],
        end_datetime: ~U[2024-04-30 23:59:59Z],
        is_ci: true,
        git_branch: "main"
      )

    assert Enum.map(breakdown, & &1.name) == names
    assert Enum.all?(breakdown, &(&1.appearances == 3 and &1.changed == 1))
    assert_received {:batch, first}
    assert first == Enum.take(names, 256)
    assert_received {:batch, ["Module257"]}
    refute_received {:batch, _}
  end

  test "a single module skips name discovery", %{project: project} do
    expect(ClickHouseRepo, :query!, fn query, params ->
      assert params.names == ["Core"]
      assert query =~ "PARTITION BY name, product, branch"
      %{rows: []}
    end)

    assert Analytics.module_invalidation_breakdown(project_id: project.id, name: "Core") == []
  end

  test "an empty project skips classification queries", %{project: project} do
    expect(ClickHouseRepo, :query!, fn query, _params ->
      assert query =~ "GROUP BY xt.name"
      %{rows: []}
    end)

    assert Analytics.module_invalidation_breakdown(project_id: project.id) == []
  end

  test "a failed later batch raises rather than returning partial analytics", %{project: project} do
    expect(ClickHouseRepo, :query!, fn _query, _params ->
      %{rows: Enum.map(1..257, &["Module#{String.pad_leading(Integer.to_string(&1), 3, "0")}"])}
    end)

    expect(ClickHouseRepo, :query!, fn _query, %{names: names} ->
      assert length(names) == 256
      %{rows: [[~D[2024-04-02], "Module001", "framework", 3, 2, 1, 0]]}
    end)

    expect(ClickHouseRepo, :query!, fn _query, %{names: ["Module257"]} ->
      raise Ch.Error, code: 159, message: "Timeout exceeded"
    end)

    assert_raise Ch.Error, fn -> Analytics.module_invalidation_breakdown(project_id: project.id) end
  end

  test "a page with no invalidated modules never reads the dependency graph", %{project: project} do
    reject(&ClickHouseRepo.query!/2)

    assert Analytics.module_invalidations_from_breakdown([], project_id: project.id) == []
  end

  test "the graph is read once and only the modules the limit returns carry a radius", %{project: project} do
    breakdown =
      Enum.map(1..40, fn index ->
        %{
          day: ~D[2024-04-02],
          name: "Module#{index}",
          product: "framework",
          appearances: 10,
          misses: index,
          changed: 1,
          upstream: 0
        }
      end)

    expect(ClickHouseRepo, :query!, fn _query, _params -> %{rows: [["latest"]]} end)

    expect(ClickHouseRepo, :query!, fn _query, _params ->
      %{rows: Enum.map(1..40, fn index -> ["Module#{index}", if(index == 40, do: [], else: ["Module40"])] end)}
    end)

    rows = Analytics.module_invalidations_from_breakdown(breakdown, project_id: project.id, limit: 2)

    assert Enum.map(rows, & &1.name) == ["Module40", "Module39"]
    assert Enum.map(rows, & &1.blast_radius) == [39, 0]
  end

  test "a module missing from the latest graph has an unknown radius", %{project: project} do
    breakdown = [
      %{day: ~D[2024-04-02], name: "Gone", product: "framework", appearances: 4, misses: 2, changed: 1, upstream: 0}
    ]

    expect(ClickHouseRepo, :query!, fn _query, _params -> %{rows: [["latest"]]} end)
    expect(ClickHouseRepo, :query!, fn _query, _params -> %{rows: [["Core", []], ["Feature", ["Core"]]]} end)

    assert [%{name: "Gone", blast_radius: nil}] =
             Analytics.module_invalidations_from_breakdown(breakdown, project_id: project.id)
  end

  test "a project without dependency edges never builds the graph join", %{project: project} do
    expect(ClickHouseRepo, :query!, fn query, params ->
      assert params.project_id == project.id
      assert query =~ "e.id IN"
      assert query =~ "notEmpty(xt.dependencies)"
      refute query =~ "JOIN"
      %{rows: [[""]]}
    end)

    assert Analytics.module_dependency_graph(project_id: project.id) == %{edges: %{}, radii: %{}}
  end

  test "compact windows retain exact names, products, branches and change classifications", %{project: project} do
    name = "Feature'東京"
    first = event(project, "first", ~N[2024-04-01 10:00:00], git_branch: nil)
    second = event(project, "second", ~N[2024-04-02 10:00:00], git_branch: "")
    third = event(project, "third", ~N[2024-04-03 10:00:00], git_branch: "")
    branch = event(project, "branch", ~N[2024-04-03 11:00:00], git_branch: "feature/東京")

    target(first, name, [], product: "framework", sources_hash: "s1", dependencies_hash: "d1")
    target(second, name, [], product: "framework", sources_hash: "s2", dependencies_hash: "d1")
    target(third, name, [], product: "framework", sources_hash: "s2", dependencies_hash: "d2")
    target(branch, name, [], product: "framework", sources_hash: "s3", dependencies_hash: "d3")
    target(third, name, [], product: "staticLibrary", sources_hash: "s3", dependencies_hash: "d3")
    target(third, "NotCacheable", [], binary_cache_hash: nil)

    rows =
      [project_id: project.id]
      |> Analytics.module_invalidation_breakdown()
      |> Enum.sort_by(&{&1.day, &1.product})

    assert Enum.map(rows, &{&1.day, &1.name, &1.product, &1.appearances, &1.misses, &1.changed, &1.upstream}) == [
             {~D[2024-04-01], name, "framework", 1, 1, 0, 0},
             {~D[2024-04-02], name, "framework", 1, 1, 1, 0},
             {~D[2024-04-03], name, "framework", 2, 2, 0, 1},
             {~D[2024-04-03], name, "staticLibrary", 1, 1, 0, 0}
           ]
  end

  test "a failed graph fetch propagates after selecting the commit", %{project: project} do
    expect(ClickHouseRepo, :query!, fn _query, _params -> %{rows: [["latest"]]} end)

    expect(ClickHouseRepo, :query!, fn query, params ->
      assert params.commit == "latest"
      assert query =~ "PREWHERE xt.command_event_id IN (SELECT id FROM selected_events)"
      raise Ch.Error, code: 159, message: "Timeout exceeded"
    end)

    assert_raise Ch.Error, fn -> Analytics.module_dependency_graph(project_id: project.id) end
  end

  test "the selected commit includes rebuilds, leaves and delayed uploads, but excludes other scopes", %{
    project: project
  } do
    old = event(project, "old", ~N[2024-04-01 10:00:00])
    target(old, "Core", [])
    target(old, "Removed", ["Core"])

    latest = event(project, "latest", ~N[2024-04-10 10:00:00])
    target(latest, "Core", [])
    target(latest, "Feature", ["Core"], inserted_at: ~N[2024-04-20 10:00:00])

    rebuild = event(project, "latest", ~N[2024-04-11 10:00:00])
    target(rebuild, "Leaf", [])

    without_edges = event(project, "newer-without-edges", ~N[2024-04-12 10:00:00])
    target(without_edges, "NoGraph", [])

    other_branch = event(project, "latest", ~N[2024-04-13 10:00:00], git_branch: "feature")
    target(other_branch, "OtherBranch", ["Core"])

    local = event(project, "latest", ~N[2024-04-14 10:00:00], is_ci: false)
    target(local, "Local", ["Core"])

    other_project = event(ProjectsFixtures.project_fixture(), "latest", ~N[2024-04-15 10:00:00])
    target(other_project, "OtherProject", ["Core"])

    outside_window = event(project, "future", ~N[2024-05-01 10:00:00])
    target(outside_window, "Future", ["Core"])

    assert Analytics.module_dependency_graph(
             project_id: project.id,
             git_branch: "main",
             is_ci: true,
             start_datetime: ~U[2024-04-01 00:00:00Z],
             end_datetime: ~U[2024-04-30 23:59:59Z]
           ) == %{
             edges: %{"Core" => [], "Feature" => ["Core"], "Leaf" => []},
             radii: %{"Core" => 1, "Feature" => 0, "Leaf" => 0}
           }
  end

  test "missing commit hashes fall back to the individual event", %{project: project} do
    old = event(project, nil, ~N[2024-04-01 10:00:00])
    target(old, "Core", [])
    target(old, "Old", ["Core"])

    latest = event(project, "", ~N[2024-04-02 10:00:00])
    target(latest, "Core", [])
    target(latest, "New", ["Core"])

    assert Analytics.module_dependency_graph(project_id: project.id).edges == %{
             "Core" => [],
             "New" => ["Core"]
           }
  end

  defp event(project, commit, created_at, opts \\ []) do
    CommandEventsFixtures.command_event_fixture(
      Keyword.merge(
        [project_id: project.id, git_commit_sha: commit, created_at: created_at, git_branch: "main", is_ci: true],
        opts
      )
    )
  end

  defp target(event, name, dependencies, opts \\ []) do
    XcodeFixtures.xcode_target_fixture(
      Keyword.merge(
        [command_event_id: event.id, name: name, binary_cache_hash: "hash", dependencies: dependencies],
        opts
      )
    )
  end
end
