defmodule TuistWeb.API.GenerationsControllerTest do
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

  describe "GET /api/projects/:account_handle/:project_handle/generations" do
    test "returns a list of generations", %{conn: conn, user: user, project: project} do
      generation =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "generate",
          duration: 5000,
          status: :success,
          git_branch: "main",
          cacheable_targets: ["TargetA", "TargetB"],
          local_cache_target_hits: ["TargetA"],
          remote_cache_target_hits: ["TargetB"],
          command_arguments: ["--no-open"],
          user_id: user.id
        )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations")

      assert %{
               "generations" => generations,
               "pagination_metadata" => _pagination
             } = json_response(conn, 200)

      assert length(generations) == 1
      [returned_generation] = generations
      assert returned_generation["id"] == generation.id
      assert returned_generation["duration"] == 5000
      assert returned_generation["status"] == "success"
      assert returned_generation["cacheable_targets"] == ["TargetA", "TargetB"]
      assert returned_generation["command_arguments"] == "--no-open"
      assert returned_generation["ran_by"] == %{"handle" => user.account.name}
    end

    test "returns empty list when no generations exist", %{conn: conn, user: user, project: project} do
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "cache"
      )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations")

      assert %{
               "generations" => [],
               "pagination_metadata" => %{
                 "total_count" => 0
               }
             } = json_response(conn, 200)
    end

    test "filters by git_branch", %{conn: conn, user: user, project: project} do
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        name: "generate",
        git_branch: "main"
      )

      generation =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "generate",
          git_branch: "feature"
        )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations?git_branch=feature")

      assert %{"generations" => [returned]} = json_response(conn, 200)
      assert returned["id"] == generation.id
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/generations/:generation_id" do
    test "returns generation details", %{conn: conn, user: user, project: project} do
      generation =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "generate",
          duration: 5000,
          status: :success,
          git_branch: "main",
          command_arguments: ["--no-open"]
        )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations/#{generation.id}")

      response = json_response(conn, 200)

      assert response["id"] == generation.id
      assert response["duration"] == 5000
      assert response["status"] == "success"
      assert response["command_arguments"] == "--no-open"
    end

    test "returns 404 when generation not found", %{conn: conn, user: user, project: project} do
      event_id = UUIDv7.generate()

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations/#{event_id}")

      assert %{"message" => "Generation not found."} = json_response(conn, 404)
    end

    test "returns 404 when event is not a generation", %{conn: conn, user: user, project: project} do
      cache_event =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "cache"
        )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations/#{cache_event.id}")

      assert %{"message" => "Generation not found."} = json_response(conn, 404)
    end

    test "returns 404 when event belongs to different project", %{conn: conn, user: user, project: project} do
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      generation =
        CommandEventsFixtures.command_event_fixture(
          project_id: other_project.id,
          name: "generate"
        )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/generations/#{generation.id}")

      assert %{"message" => "Generation not found."} = json_response(conn, 404)
    end
  end
end
