defmodule Tuist.MCP.Components.Tools.ModuleCacheToolsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.MCP.Components.Tools.GetXcodeModule
  alias Tuist.MCP.Components.Tools.GetXcodeModuleCacheTimeseries
  alias Tuist.MCP.Components.Tools.ListXcodeModuleBuilds
  alias Tuist.MCP.Components.Tools.ListXcodeModuleInvalidations
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures

  @window %{
    "account_handle" => "acme",
    "project_handle" => "app",
    "start_datetime" => "2024-04-01T00:00:00Z",
    "end_datetime" => "2024-04-30T23:59:59Z"
  }

  setup do
    stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
    project = ProjectsFixtures.project_fixture(default_branch: "main")

    stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)
    stub(Tuist.Authorization, :authorize, fn _action, _subject, _project -> :ok end)

    %{project: project, conn: %Plug.Conn{assigns: %{}}}
  end

  defp build(project, created_at, targets, opts \\ []) do
    event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        git_branch: Keyword.get(opts, :git_branch, "main"),
        git_commit_sha: Keyword.get(opts, :git_commit_sha, "sha-#{created_at}"),
        is_ci: Keyword.get(opts, :is_ci, true),
        created_at: created_at
      )

    for {name, hit, sources, deps} <- targets do
      XcodeFixtures.xcode_target_fixture(
        command_event_id: event.id,
        name: name,
        product: "framework",
        binary_cache_hash: "h-#{name}-#{sources}",
        binary_cache_hit: hit,
        sources_hash: sources,
        dependencies_hash: "subhash-#{name}",
        dependencies: deps
      )
    end

    event
  end

  defp decode(%{"content" => [%{"text" => json}]}), do: JSON.decode!(json)

  describe "list_xcode_module_invalidations" do
    test "ranks modules by invalidations and counts the project's modules", %{project: project, conn: conn} do
      build(project, ~N[2024-04-01 10:00:00], [
        {"Core", :miss, "c1", []},
        {"Networking", :miss, "n1", ["Core"]}
      ])

      build(project, ~N[2024-04-02 10:00:00], [
        {"Core", :remote, "c1", []},
        {"Networking", :miss, "n2", ["Core"]}
      ])

      data = conn |> ListXcodeModuleInvalidations.call(@window) |> decode()

      assert [networking, core] = data["modules"]
      assert networking["name"] == "Networking"
      assert networking["invalidations"] == 2
      assert networking["self_changes"] == 1
      assert networking["blast_radius"] == 0

      assert core["name"] == "Core"
      assert core["appearances"] == 2
      assert core["invalidations"] == 1
      assert core["blast_radius"] == 1

      assert data["module_count"] == 2
      assert data["module_count_branch"] == "main"
    end

    test "honours the limit, branch and environment filters", %{project: project, conn: conn} do
      build(project, ~N[2024-04-01 10:00:00], [{"Core", :miss, "c1", []}, {"App", :miss, "a1", []}])
      build(project, ~N[2024-04-03 10:00:00], [{"Feature", :miss, "f1", []}], git_branch: "feature/x")
      build(project, ~N[2024-04-04 10:00:00], [{"Local", :miss, "l1", []}], is_ci: false)

      limited = conn |> ListXcodeModuleInvalidations.call(Map.put(@window, "limit", 1)) |> decode()
      assert length(limited["modules"]) == 1

      branched = conn |> ListXcodeModuleInvalidations.call(Map.put(@window, "git_branch", "feature/x")) |> decode()
      assert Enum.map(branched["modules"], & &1["name"]) == ["Feature"]
      assert branched["module_count_branch"] == "feature/x"

      local = conn |> ListXcodeModuleInvalidations.call(Map.put(@window, "is_ci", false)) |> decode()
      assert Enum.map(local["modules"], & &1["name"]) == ["Local"]
    end

    test "rejects a datetime that is not ISO 8601", %{conn: conn} do
      assert %{"isError" => true, "content" => [%{"text" => message}]} =
               ListXcodeModuleInvalidations.call(conn, Map.put(@window, "start_datetime", "yesterday"))

      assert message =~ "start_datetime must be an ISO 8601 datetime."
    end
  end

  describe "get_xcode_module" do
    test "returns the module's dependency graph edges, not its dependencies subhash", %{project: project, conn: conn} do
      build(project, ~N[2024-04-01 10:00:00], [
        {"Core", :miss, "c1", []},
        {"Networking", :miss, "n1", ["Core"]},
        {"App", :miss, "a1", ["Networking"]}
      ])

      data = conn |> GetXcodeModule.call(Map.put(@window, "name", "Core")) |> decode()

      assert data["name"] == "Core"
      assert data["invalidations"] == 1
      assert data["depends_on"] == []
      assert data["dependents"] == ["Networking"]
      assert data["transitive_dependents"] == ["App", "Networking"]
      assert data["blast_radius"] == 2
      # `dependencies` on a module cache target is the subhash, so nothing here
      # may carry that name: these are the graph edges.
      refute Map.has_key?(data, "dependencies")
    end

    test "returns a zeroed row for a module that only ever reused from cache", %{project: project, conn: conn} do
      build(project, ~N[2024-04-01 10:00:00], [{"Core", :remote, "c1", []}, {"App", :miss, "a1", ["Core"]}])
      build(project, ~N[2024-04-02 10:00:00], [{"Core", :local, "c1", []}, {"App", :miss, "a2", ["Core"]}])

      data = conn |> GetXcodeModule.call(Map.put(@window, "name", "Core")) |> decode()

      assert data["appearances"] == 2
      assert data["invalidations"] == 0
      assert data["hit_rate"] == 100.0
      assert data["blast_radius"] == 1
      assert data["dependents"] == ["App"]
    end

    test "nulls the graph fields when no build carries dependency edges", %{project: project, conn: conn} do
      build(project, ~N[2024-04-01 10:00:00], [{"Core", :miss, "c1", []}, {"App", :miss, "a1", []}])

      data = conn |> GetXcodeModule.call(Map.put(@window, "name", "Core")) |> decode()

      assert data["depends_on"] == nil
      assert data["dependents"] == nil
      assert data["transitive_dependents"] == nil
      assert data["blast_radius"] == nil
    end

    test "errors for a module no build in the window carries", %{project: project, conn: conn} do
      build(project, ~N[2024-04-01 10:00:00], [{"Core", :miss, "c1", []}])

      assert %{"isError" => true, "content" => [%{"text" => message}]} =
               GetXcodeModule.call(conn, Map.put(@window, "name", "Gone"))

      assert message =~ "Module not found: Gone"
    end
  end

  describe "list_xcode_module_builds" do
    test "returns one row per build with why the module missed", %{project: project, conn: conn} do
      build(project, ~N[2024-04-01 10:00:00], [{"Core", :miss, "c1", []}], git_commit_sha: "aaa111")
      build(project, ~N[2024-04-02 10:00:00], [{"Core", :remote, "c1", []}], git_commit_sha: "bbb222")
      build(project, ~N[2024-04-03 10:00:00], [{"Core", :miss, "c2", []}], git_commit_sha: "ccc333")

      data = conn |> ListXcodeModuleBuilds.call(Map.put(@window, "name", "Core")) |> decode()

      assert Enum.map(data["builds"], & &1["reason"]) == ["changed", "hit", "cold"]
      assert Enum.map(data["builds"], & &1["cache_status"]) == ["miss", "remote", "miss"]
      assert Enum.map(data["builds"], & &1["git_commit_sha"]) == ["ccc333", "bbb222", "aaa111"]
      assert hd(data["builds"])["git_branch"] == "main"
      assert hd(data["builds"])["ran_at"] == "2024-04-03T10:00:00Z"
      refute data["pagination_metadata"]["has_next_page"]
      refute data["pagination_metadata"]["has_previous_page"]
    end

    test "walks pages with the cursors it returns", %{project: project, conn: conn} do
      for day <- 1..5 do
        build(project, ~D[2024-04-01] |> NaiveDateTime.new!(~T[10:00:00]) |> NaiveDateTime.add(day, :day), [
          {"Core", :miss, "c#{day}", []}
        ])
      end

      args = @window |> Map.put("name", "Core") |> Map.put("limit", 2)
      first = conn |> ListXcodeModuleBuilds.call(args) |> decode()

      assert length(first["builds"]) == 2
      assert first["pagination_metadata"]["has_next_page"]
      refute first["pagination_metadata"]["has_previous_page"]

      second =
        conn
        |> ListXcodeModuleBuilds.call(Map.put(args, "after", first["pagination_metadata"]["end_cursor"]))
        |> decode()

      assert length(second["builds"]) == 2
      assert second["pagination_metadata"]["has_previous_page"]
      assert Enum.map(second["builds"], & &1["run_id"]) != Enum.map(first["builds"], & &1["run_id"])

      back =
        conn
        |> ListXcodeModuleBuilds.call(Map.put(args, "before", second["pagination_metadata"]["start_cursor"]))
        |> decode()

      assert Enum.map(back["builds"], & &1["run_id"]) == Enum.map(first["builds"], & &1["run_id"])
    end

    test "filters by reason, commit prefix and order", %{project: project, conn: conn} do
      build(project, ~N[2024-04-01 10:00:00], [{"Core", :miss, "c1", []}], git_commit_sha: "aaa111")
      build(project, ~N[2024-04-02 10:00:00], [{"Core", :remote, "c1", []}], git_commit_sha: "bbb222")
      build(project, ~N[2024-04-03 10:00:00], [{"Core", :miss, "c2", []}], git_commit_sha: "aaa333")

      args = Map.put(@window, "name", "Core")

      hits = conn |> ListXcodeModuleBuilds.call(Map.put(args, "reason", "hit")) |> decode()
      assert Enum.map(hits["builds"], & &1["git_commit_sha"]) == ["bbb222"]

      prefixed = conn |> ListXcodeModuleBuilds.call(Map.put(args, "commit_sha", "aaa")) |> decode()
      assert Enum.map(prefixed["builds"], & &1["git_commit_sha"]) == ["aaa333", "aaa111"]

      ascending = conn |> ListXcodeModuleBuilds.call(Map.put(args, "order", "asc")) |> decode()
      assert Enum.map(ascending["builds"], & &1["git_commit_sha"]) == ["aaa111", "bbb222", "aaa333"]
    end

    test "refuses both cursors at once", %{conn: conn} do
      args = @window |> Map.put("name", "Core") |> Map.put("after", "a") |> Map.put("before", "b")

      assert %{"isError" => true, "content" => [%{"text" => message}]} = ListXcodeModuleBuilds.call(conn, args)
      assert message =~ "Use only one of after or before."
    end
  end

  describe "get_xcode_module_cache_timeseries" do
    test "returns the project-wide series when no module is named", %{project: project, conn: conn} do
      build(project, ~N[2024-04-10 10:00:00], [{"Core", :miss, "c1", []}, {"App", :remote, "a1", ["Core"]}])
      build(project, ~N[2024-04-11 10:00:00], [{"Core", :miss, "c2", []}, {"App", :remote, "a1", ["Core"]}])

      data = conn |> GetXcodeModuleCacheTimeseries.call(@window) |> decode()

      assert length(data["dates"]) == 30
      assert Enum.sum(data["invalidations"]) == 2
      assert Enum.sum(data["reuses"]) == 2
      assert Enum.sum(data["miss_reasons"]["changed"]) == 1
      assert Enum.sum(data["miss_reasons"]["cold"]) == 1
      assert data["dependents_counts"] == nil

      index = Enum.find_index(data["dates"], &(&1 == "2024-04-10"))
      assert Enum.at(data["module_counts"], index) == 2
      assert Enum.at(data["hit_rates"], index) == 50.0
    end

    test "scopes the cache series to one module and adds its dependents", %{project: project, conn: conn} do
      build(project, ~N[2024-04-10 10:00:00], [{"Core", :miss, "c1", []}, {"App", :remote, "a1", ["Core"]}])

      data = conn |> GetXcodeModuleCacheTimeseries.call(Map.put(@window, "name", "Core")) |> decode()

      assert Enum.sum(data["invalidations"]) == 1
      assert Enum.sum(data["reuses"]) == 0

      index = Enum.find_index(data["dates"], &(&1 == "2024-04-10"))
      assert Enum.at(data["dependents_counts"], index) == 1
      # Never scoped to the named module.
      assert Enum.at(data["module_counts"], index) == 2
    end
  end
end
