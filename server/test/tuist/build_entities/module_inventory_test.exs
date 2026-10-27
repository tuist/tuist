defmodule Tuist.BuildEntities.ModuleInventoryTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.BuildEntities
  alias Tuist.BuildEntities.QueryLimitError
  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents.Event
  alias Tuist.IngestRepo
  alias Tuist.Xcode
  alias Tuist.Xcode.XcodeGraph
  alias TuistTestSupport.Fixtures.BuildEntitiesFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures

  setup do
    project = ProjectsFixtures.project_fixture()
    start_at = DateTime.new!(Date.add(Date.utc_today(), -3), ~T[00:00:00])
    end_at = DateTime.add(start_at, 3, :day)
    %{project: project, start_at: start_at, end_at: end_at, window: [start_datetime: start_at, end_datetime: end_at]}
  end

  test "uses default-branch graph state, including removals, and carries it over days without builds", context do
    %{project: project, start_at: start_at, end_at: end_at, window: window} = context
    graph(project, "trunk", DateTime.add(start_at, -1, :day), 8)
    graph(project, "trunk", DateTime.add(start_at, 1, :hour), 5, is_ci: false)
    graph(project, "trunk", DateTime.add(start_at, 2, :day), 3)
    graph(project, "feature", DateTime.add(end_at, -1, :hour), 99)
    graph(project, "trunk", DateTime.add(end_at, 1, :hour), 200)
    graph(ProjectsFixtures.project_fixture(), "trunk", DateTime.add(end_at, -1, :hour), 300)

    BuildEntitiesFixtures.entity_fixture(project, :xcode_modules, duration_ms: nil, cache_status: "hit_remote")
    result = BuildEntities.default_branch_module_counts(project.id, "trunk", window ++ [environment: "ci"])
    assert result.total == 3
    assert result.previous == 8
    assert Enum.map(result.points, & &1.entities) == [5, 5, 3]
    assert length(result.points) == 3
  end

  test "a graph before the selected period still supplies state when no modules build in the period", context do
    %{project: project, start_at: start_at, window: window} = context
    graph(project, "main", DateTime.add(start_at, -2, :day), 4)
    result = BuildEntities.default_branch_module_counts(project.id, "main", window)
    assert result.total == result.previous
    assert result.total == 4
    assert Enum.all?(result.points, &(&1.entities == 4))
  end

  test "unknown legacy graphs and missing default branches stay unavailable rather than resurrecting old counts",
       context do
    %{project: project, start_at: start_at, window: window} = context
    graph(project, "main", DateTime.add(start_at, -1, :day), 4)
    graph(project, "main", DateTime.add(start_at, 1, :hour), nil)
    result = BuildEntities.default_branch_module_counts(project.id, "main", window)
    assert result.previous == 4
    assert result.total == nil
    assert Enum.all?(result.points, &is_nil(&1.entities))
    assert BuildEntities.default_branch_module_counts(project.id, "missing", window).total == nil
    reject(ClickHouseRepo, :query, 3)
    assert BuildEntities.default_branch_module_counts(project.id, nil, window).total == nil
    assert BuildEntities.default_branch_module_counts(project.id, "", window).total == nil
  end

  test "native graph ingestion counts project/module pairs, not just cacheable or executed targets", context do
    %{project: project, start_at: start_at, window: window} = context

    event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        git_branch: "main",
        ran_at: DateTime.add(start_at, 1, :hour)
      )

    with_flushed_ingestion_buffers(fn ->
      Xcode.create_xcode_graph(%{
        command_event: event,
        xcode_graph: %{
          name: "Workspace",
          projects: [
            %{"name" => "App", "path" => "App", "targets" => [%{"name" => "Core"}, %{"name" => "App"}]},
            %{"name" => "Tools", "path" => "Tools", "targets" => [%{"name" => "Core"}]}
          ]
        }
      })
    end)

    assert BuildEntities.default_branch_module_counts(project.id, "main", window).total == 3
    [stored] = ClickHouseRepo.all(from(g in XcodeGraph, where: g.command_event_id == ^event.id))
    assert stored.modules_count == 3
  end

  test "a reported empty graph is a measured zero, not missing state", context do
    %{project: project, start_at: start_at, window: window} = context

    event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        git_branch: "main",
        ran_at: DateTime.add(start_at, 1, :hour)
      )

    with_flushed_ingestion_buffers(fn ->
      Xcode.create_xcode_graph(%{command_event: event, xcode_graph: %{name: "Empty", projects: []}})
    end)

    result = BuildEntities.default_branch_module_counts(project.id, "main", window)
    assert result.total == 0
    assert result.previous == nil
    assert Enum.all?(result.points, &(&1.entities == 0))
  end

  test "same-day period boundaries retain the state before the start separately from the end", context do
    %{project: project, start_at: start_at} = context
    start_at = DateTime.add(start_at, 12, :hour)
    graph(project, "main", DateTime.add(start_at, -1, :hour), 7)
    graph(project, "main", DateTime.add(start_at, 1, :hour), 2)

    result =
      BuildEntities.default_branch_module_counts(project.id, "main",
        start_datetime: start_at,
        end_datetime: DateTime.add(start_at, 2, :hour)
      )

    assert result.total == 2
    assert result.previous == 7
    assert [%{entities: 2}] = result.points
  end

  test "tenant-scoped graph headers isolate even colliding native command event IDs", context do
    %{project: project, start_at: start_at, window: window} = context
    own = graph(project, "main", DateTime.add(start_at, 3600), 5)
    other = ProjectsFixtures.project_fixture()
    graph(other, "main", DateTime.add(start_at, 3600), 999, id: own.command_event_id)
    XcodeFixtures.xcode_graph_fixture(command_event_id: own.command_event_id, modules_count: 777, project_id: 0)
    assert BuildEntities.default_branch_module_counts(project.id, "main", window).total == 5
    assert BuildEntities.default_branch_module_counts(other.id, "main", window).total == 999
  end

  test "command event branch and time corrections resolve before default-branch period filters", context do
    %{project: project, start_at: start_at, end_at: end_at, window: window} = context
    graph(project, "main", DateTime.add(start_at, -3600), 5)
    moved_branch = graph(project, "main", DateTime.add(start_at, 3600), 12)
    correct_event(moved_branch.event, git_branch: "feature")
    moved_into_branch = graph(project, "feature", DateTime.add(start_at, 7200), 9)
    correct_event(moved_into_branch.event, git_branch: "main")
    moved_time = graph(project, "main", DateTime.add(start_at, 10_800), 22)
    correct_event(moved_time.event, ran_at: DateTime.to_naive(DateTime.add(end_at, 3600)))
    cleared = graph(project, "main", DateTime.add(start_at, 14_400), 33)
    correct_event(cleared.event, git_branch: nil)
    result = BuildEntities.default_branch_module_counts(project.id, "main", window)
    assert result.total == 9
    assert result.previous == 5
    assert Enum.all?(result.points, &(&1.entities == 9))
  end

  test "query limits propagate and keep the normal bounded read settings", context do
    %{project: project, window: window} = context

    expect(ClickHouseRepo, :query, fn sql, params, opts ->
      assert sql =~ "project_id = {project_id:Int64}"
      assert params.branch == "main' OR 1=1 --"
      assert opts[:settings][:max_memory_usage] <= 536_870_912
      assert opts[:settings][:max_execution_time] <= 30
      {:error, %Ch.Error{code: 159, message: "timeout"}}
    end)

    assert_raise QueryLimitError, fn ->
      BuildEntities.default_branch_module_counts(project.id, "main' OR 1=1 --", window)
    end
  end

  defp graph(project, branch, ran_at, count, attrs \\ []) do
    event =
      CommandEventsFixtures.command_event_fixture([project_id: project.id, git_branch: branch, ran_at: ran_at] ++ attrs)

    [command_event_id: event.id, project_id: project.id, modules_count: count]
    |> XcodeFixtures.xcode_graph_fixture()
    |> Map.put(:event, event)
  end

  defp correct_event(event, changes) do
    attrs =
      event
      |> Map.take([:id, :name, :project_id, :ran_at, :git_branch, :created_at])
      |> Map.merge(Map.new(changes))
      |> Map.put(:updated_at, NaiveDateTime.add(event.updated_at, 1, :second))
      |> Event.changeset()

    IngestRepo.insert_all(Event, [attrs])
  end
end
