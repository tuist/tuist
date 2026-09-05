defmodule TuistWeb.API.ModuleCacheControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.XcodeFixtures
  alias TuistWeb.Authentication

  @window %{
    "start_datetime" => "2024-04-01T00:00:00Z",
    "end_datetime" => "2024-04-30T23:59:59Z"
  }

  setup %{conn: conn} do
    stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, default_branch: "main")

    %{
      conn: Authentication.put_current_user(conn, user),
      project: project,
      base: "/api/projects/#{user.account.name}/#{project.name}/module-cache"
    }
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

  describe "GET /module-cache/modules" do
    test "ranks modules by invalidations and counts the project's modules", %{
      conn: conn,
      project: project,
      base: base
    } do
      build(project, ~N[2024-04-01 10:00:00], [{"Core", :miss, "c1", []}, {"Networking", :miss, "n1", ["Core"]}])
      build(project, ~N[2024-04-02 10:00:00], [{"Core", :remote, "c1", []}, {"Networking", :miss, "n2", ["Core"]}])

      response = conn |> get("#{base}/modules", @window) |> json_response(:ok)

      assert [networking, core] = response["modules"]
      assert networking["name"] == "Networking"
      assert networking["invalidations"] == 2
      assert networking["self_changes"] == 1
      assert core["name"] == "Core"
      assert core["blast_radius"] == 1

      assert response["module_count"] == 2
      assert response["module_count_branch"] == "main"
    end

    test "honours limit, branch and environment", %{conn: conn, project: project, base: base} do
      build(project, ~N[2024-04-01 10:00:00], [{"Core", :miss, "c1", []}, {"App", :miss, "a1", []}])
      build(project, ~N[2024-04-03 10:00:00], [{"Feature", :miss, "f1", []}], git_branch: "feature/x")
      build(project, ~N[2024-04-04 10:00:00], [{"Local", :miss, "l1", []}], is_ci: false)

      limited = conn |> get("#{base}/modules", Map.put(@window, "limit", "1")) |> json_response(:ok)
      assert length(limited["modules"]) == 1

      branched = conn |> get("#{base}/modules", Map.put(@window, "git_branch", "feature/x")) |> json_response(:ok)
      assert Enum.map(branched["modules"], & &1["name"]) == ["Feature"]
      assert branched["module_count_branch"] == "feature/x"

      local = conn |> get("#{base}/modules", Map.put(@window, "is_ci", "false")) |> json_response(:ok)
      assert Enum.map(local["modules"], & &1["name"]) == ["Local"]
    end

    test "rejects a datetime that is not ISO 8601", %{conn: conn, base: base} do
      conn = get(conn, "#{base}/modules", Map.put(@window, "start_datetime", "yesterday"))

      assert json_response(conn, :bad_request)
    end
  end

  describe "GET /module-cache/modules/:module_name" do
    test "returns the dependency graph edges, not the dependencies subhash", %{
      conn: conn,
      project: project,
      base: base
    } do
      build(project, ~N[2024-04-01 10:00:00], [
        {"Core", :miss, "c1", []},
        {"Networking", :miss, "n1", ["Core"]},
        {"App", :miss, "a1", ["Networking"]}
      ])

      response = conn |> get("#{base}/modules/Core", @window) |> json_response(:ok)

      assert response["name"] == "Core"
      assert response["depends_on"] == []
      assert response["dependents"] == ["Networking"]
      assert response["transitive_dependents"] == ["App", "Networking"]
      assert response["blast_radius"] == 2
      # `dependencies` names the subhash on a module cache target, so the edges
      # must never reuse it.
      refute Map.has_key?(response, "dependencies")
    end

    test "returns a zeroed row for a module that only ever reused from cache", %{
      conn: conn,
      project: project,
      base: base
    } do
      build(project, ~N[2024-04-01 10:00:00], [{"Core", :remote, "c1", []}, {"App", :miss, "a1", ["Core"]}])
      build(project, ~N[2024-04-02 10:00:00], [{"Core", :local, "c1", []}, {"App", :miss, "a2", ["Core"]}])

      response = conn |> get("#{base}/modules/Core", @window) |> json_response(:ok)

      assert response["appearances"] == 2
      assert response["invalidations"] == 0
      assert response["hit_rate"] == 100.0
      assert response["blast_radius"] == 1
    end

    test "404s a module no build in the window carries", %{conn: conn, project: project, base: base} do
      build(project, ~N[2024-04-01 10:00:00], [{"Core", :miss, "c1", []}])

      assert conn |> get("#{base}/modules/Gone", @window) |> json_response(:not_found)
    end
  end

  describe "GET /module-cache/modules/:module_name/builds" do
    test "returns one row per build with why the module missed", %{conn: conn, project: project, base: base} do
      build(project, ~N[2024-04-01 10:00:00], [{"Core", :miss, "c1", []}], git_commit_sha: "aaa111")
      build(project, ~N[2024-04-02 10:00:00], [{"Core", :remote, "c1", []}], git_commit_sha: "bbb222")
      build(project, ~N[2024-04-03 10:00:00], [{"Core", :miss, "c2", []}], git_commit_sha: "ccc333")

      response = conn |> get("#{base}/modules/Core/builds", @window) |> json_response(:ok)

      assert Enum.map(response["builds"], & &1["reason"]) == ["changed", "hit", "cold"]
      assert Enum.map(response["builds"], & &1["cache_status"]) == ["miss", "remote", "miss"]
      assert hd(response["builds"])["ran_at"] == "2024-04-03T10:00:00Z"
      assert response["pagination_metadata"]["page_size"] == 25
      refute response["pagination_metadata"]["has_next_page"]
    end

    test "walks pages with the cursors it returns", %{conn: conn, project: project, base: base} do
      for day <- 1..5 do
        build(
          project,
          NaiveDateTime.add(NaiveDateTime.new!(~D[2024-04-01], ~T[10:00:00]), day, :day),
          [{"Core", :miss, "c#{day}", []}]
        )
      end

      params = Map.put(@window, "limit", "2")
      first = conn |> get("#{base}/modules/Core/builds", params) |> json_response(:ok)

      assert length(first["builds"]) == 2
      assert first["pagination_metadata"]["has_next_page"]

      second =
        conn
        |> get("#{base}/modules/Core/builds", Map.put(params, "after", first["pagination_metadata"]["end_cursor"]))
        |> json_response(:ok)

      assert second["pagination_metadata"]["has_previous_page"]
      assert Enum.map(second["builds"], & &1["run_id"]) != Enum.map(first["builds"], & &1["run_id"])
    end

    test "refuses both cursors at once", %{conn: conn, base: base} do
      params = @window |> Map.put("after", "a") |> Map.put("before", "b")

      assert conn |> get("#{base}/modules/Core/builds", params) |> json_response(:bad_request)
    end
  end

  describe "GET /module-cache/metrics" do
    test "returns the project-wide series when no module is named", %{conn: conn, project: project, base: base} do
      build(project, ~N[2024-04-10 10:00:00], [{"Core", :miss, "c1", []}, {"App", :remote, "a1", ["Core"]}])
      build(project, ~N[2024-04-11 10:00:00], [{"Core", :miss, "c2", []}, {"App", :remote, "a1", ["Core"]}])

      response = conn |> get("#{base}/metrics", @window) |> json_response(:ok)

      assert length(response["dates"]) == 30
      assert Enum.sum(response["invalidations"]) == 2
      assert Enum.sum(response["reuses"]) == 2
      assert Enum.sum(response["miss_reasons"]["changed"]) == 1
      assert response["dependents_counts"] == nil

      index = Enum.find_index(response["dates"], &(&1 == "2024-04-10"))
      assert Enum.at(response["module_counts"], index) == 2
      assert Enum.at(response["hit_rates"], index) == 50.0
    end

    test "scopes the cache series to one module and adds its dependents", %{
      conn: conn,
      project: project,
      base: base
    } do
      build(project, ~N[2024-04-10 10:00:00], [{"Core", :miss, "c1", []}, {"App", :remote, "a1", ["Core"]}])

      response = conn |> get("#{base}/metrics", Map.put(@window, "name", "Core")) |> json_response(:ok)

      assert Enum.sum(response["invalidations"]) == 1
      assert Enum.sum(response["reuses"]) == 0

      index = Enum.find_index(response["dates"], &(&1 == "2024-04-10"))
      assert Enum.at(response["dependents_counts"], index) == 1
      assert Enum.at(response["module_counts"], index) == 2
    end
  end
end
