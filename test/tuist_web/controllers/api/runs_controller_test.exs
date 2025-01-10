defmodule TuistWeb.API.RunsControllerTest do
  alias TuistWeb.Authentication
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  use TuistTestSupport.Cases.ConnCase, async: true

  describe "GET /api/projects/:account_handle/:project_handle/runs" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn =
        conn
        |> Authentication.put_current_user(user)

      %{conn: conn, user: user, project: project}
    end

    test "lists two project runs", %{conn: conn, user: user, project: project} do
      # Given
      _run_one =
        CommandEventsFixtures.command_event_fixture(project_id: project.id)

      run_two = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      run_three = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      _run_four = CommandEventsFixtures.command_event_fixture()

      # When
      conn =
        conn
        |> get("/api/projects/#{user.account.name}/#{project.name}/runs?page_size=2")

      # Then
      response = json_response(conn, :ok)

      assert response["runs"] |> Enum.map(& &1["id"]) == [
               run_three.id,
               run_two.id
             ]
    end

    test "lists second page", %{conn: conn, user: user, project: project} do
      # Given
      run_one =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "test",
          test_targets: ["ATests", "BTests", "CTests"],
          local_test_target_hits: ["ATests", "BTests"],
          remote_test_target_hits: ["CTests"],
          cacheable_targets: ["A", "B", "C"],
          local_cache_target_hits: ["A", "B"],
          remote_cache_target_hits: ["C"]
        )

      _run_two = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      _run_three = CommandEventsFixtures.command_event_fixture(project_id: project.id)
      _run_four = CommandEventsFixtures.command_event_fixture()

      # When
      conn =
        conn
        |> get("/api/projects/#{user.account.name}/#{project.name}/runs?page=2&page_size=2")

      # Then
      response = json_response(conn, :ok)

      assert response["runs"] == [
               %{
                 "id" => run_one.id,
                 "git_branch" => nil,
                 "git_commit_sha" => nil,
                 "cacheable_targets" => ["A", "B", "C"],
                 "command_arguments" => nil,
                 "duration" => 0,
                 "git_ref" => nil,
                 "local_cache_target_hits" => ["A", "B"],
                 "local_test_target_hits" => ["ATests", "BTests"],
                 "macos_version" => "10.15",
                 "name" => "test",
                 "preview_id" => nil,
                 "remote_cache_target_hits" => ["C"],
                 "remote_test_target_hits" => ["CTests"],
                 "status" => "success",
                 "subcommand" => nil,
                 "swift_version" => "5.2",
                 "test_targets" => ["ATests", "BTests", "CTests"],
                 "tuist_version" => "4.1.0",
                 "url" => "/#{user.account.name}/#{project.name}/runs/#{run_one.id}"
               }
             ]
    end

    test "lists no runs when there are none", %{conn: conn, user: user, project: project} do
      # Given
      # No runs are created

      # When
      conn =
        conn
        |> get("/api/projects/#{user.account.name}/#{project.name}/runs")

      # Then
      response = json_response(conn, :ok)

      assert response["runs"] == []
    end

    test "filters runs based on git_ref and name", %{conn: conn, user: user, project: project} do
      # Given
      run_one =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          git_ref: "refs/heads/main",
          name: "test"
        )

      _run_two =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          git_ref: "refs/heads/feature",
          name: "test"
        )

      _run_three =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          git_ref: "refs/heads/main",
          name: "build"
        )

      # When
      conn =
        conn
        |> get(
          "/api/projects/#{user.account.name}/#{project.name}/runs?git_ref=refs/heads/main&name=test"
        )

      # Then
      response = json_response(conn, :ok)

      assert response["runs"] == [
               %{
                 "id" => run_one.id,
                 "git_branch" => nil,
                 "git_commit_sha" => nil,
                 "cacheable_targets" => [],
                 "command_arguments" => nil,
                 "duration" => 0,
                 "git_ref" => "refs/heads/main",
                 "local_cache_target_hits" => [],
                 "local_test_target_hits" => [],
                 "macos_version" => "10.15",
                 "name" => "test",
                 "preview_id" => nil,
                 "remote_cache_target_hits" => [],
                 "remote_test_target_hits" => [],
                 "status" => "success",
                 "subcommand" => nil,
                 "swift_version" => "5.2",
                 "test_targets" => [],
                 "tuist_version" => "4.1.0",
                 "url" => "/#{user.account.name}/#{project.name}/runs/#{run_one.id}"
               }
             ]
    end

    test "returns forbidden response when the user doesn't have access to the project", %{
      conn: conn
    } do
      # Given
      another_user = AccountsFixtures.user_fixture(preload: [:account])
      another_project = ProjectsFixtures.project_fixture(account_id: another_user.account.id)

      # When
      conn =
        conn
        |> get("/api/projects/#{another_user.account.name}/#{another_project.name}/runs")

      # Then
      assert response(conn, :forbidden)
    end

    test "returns not found response when the project is not found", %{conn: conn, user: user} do
      # Given
      non_existent_project_name = "non-existent-project"

      # When
      conn =
        conn
        |> get("/api/projects/#{user.account.name}/#{non_existent_project_name}/runs")

      # Then
      assert response(conn, :not_found)
    end
  end
end
