defmodule TuistWeb.API.CacheRunsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    conn = assign(conn, :selected_project, project)

    %{conn: conn, user: user, project: project}
  end

  describe "GET /api/projects/:account_handle/:project_handle/cache-runs" do
    test "returns a list of cache runs", %{conn: conn, user: user, project: project} do
      cache_run =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "cache",
          duration: 12_000,
          status: :success,
          is_ci: true,
          git_branch: "main",
          cacheable_targets: ["TargetA", "TargetB", "TargetC"],
          local_cache_target_hits: [],
          remote_cache_target_hits: []
        )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/cache-runs")

      assert %{
               "cache_runs" => cache_runs,
               "pagination_metadata" => _pagination
             } = json_response(conn, 200)

      assert length(cache_runs) == 1
      [returned_cache_run] = cache_runs
      assert returned_cache_run["id"] == cache_run.id
      assert returned_cache_run["duration"] == 12_000
      assert returned_cache_run["status"] == "success"
      assert returned_cache_run["is_ci"] == true
      assert returned_cache_run["cacheable_targets"] == ["TargetA", "TargetB", "TargetC"]
    end

    test "returns empty list when no cache runs exist", %{conn: conn, user: user, project: project} do
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate"
      )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/cache-runs")

      assert %{
               "cache_runs" => [],
               "pagination_metadata" => %{
                 "total_count" => 0
               }
             } = json_response(conn, 200)
    end

    test "filters by git_branch", %{conn: conn, user: user, project: project} do
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "cache",
        git_branch: "main"
      )

      cache_run =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "cache",
          git_branch: "feature"
        )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/cache-runs?git_branch=feature")

      assert %{"cache_runs" => [returned]} = json_response(conn, 200)
      assert returned["id"] == cache_run.id
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/cache-runs/:cache_run_id" do
    test "returns cache run details", %{conn: conn, user: user, project: project} do
      cache_run =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "cache",
          duration: 12_000,
          status: :success,
          is_ci: true,
          git_branch: "main",
          command_arguments: ["warm"]
        )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/cache-runs/#{cache_run.id}")

      response = json_response(conn, 200)

      assert response["id"] == cache_run.id
      assert response["duration"] == 12_000
      assert response["status"] == "success"
      assert response["command_arguments"] == "warm"
    end

    test "returns 404 when cache run not found", %{conn: conn, user: user, project: project} do
      event_id = UUIDv7.generate()

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/cache-runs/#{event_id}")

      assert %{"message" => "Cache run not found."} = json_response(conn, 404)
    end

    test "returns 404 when event is not a cache run", %{conn: conn, user: user, project: project} do
      generate_event =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "generate"
        )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/cache-runs/#{generate_event.id}")

      assert %{"message" => "Cache run not found."} = json_response(conn, 404)
    end

    test "returns 404 when event belongs to different project", %{conn: conn, user: user, project: project} do
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      cache_run =
        CommandEventsFixtures.command_event_fixture(
          project_id: other_project.id,
          name: "cache"
        )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/cache-runs/#{cache_run.id}")

      assert %{"message" => "Cache run not found."} = json_response(conn, 404)
    end
  end
end
