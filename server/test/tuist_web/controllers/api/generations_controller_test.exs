defmodule TuistWeb.API.GenerationsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  describe "GET /api/projects/:account_handle/:project_handle/generations" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "lists only generate runs for the project", %{conn: conn, user: user, project: project} do
      _generation_one =
        CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "generate")

      generation_two = CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "generate")
      _other_command = CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "cache")
      _other_project = CommandEventsFixtures.command_event_fixture(name: "generate")

      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/generations?page_size=1"
        )

      response = json_response(conn, :ok)

      assert length(response["runs"]) == 1
      assert hd(response["runs"])["url"] =~ generation_two.id
    end

    test "returns forbidden response when the user doesn't have access to the project", %{conn: conn} do
      another_user = AccountsFixtures.user_fixture(preload: [:account])
      another_project = ProjectsFixtures.project_fixture(account_id: another_user.account.id)

      conn =
        get(conn, "/api/projects/#{another_user.account.name}/#{another_project.name}/generations")

      assert response(conn, :forbidden)
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/generations/:run_id" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "shows a generation", %{conn: conn, user: user, project: project} do
      generation =
        CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "generate")

      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/generations/#{generation.id}"
        )

      response = json_response(conn, :ok)
      assert response["name"] == "generate"
      assert response["url"] =~ generation.id
    end

    test "returns not found when the run isn't a generation", %{conn: conn, user: user, project: project} do
      cache_run =
        CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "cache")

      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/generations/#{cache_run.id}"
        )

      assert response(conn, :not_found)
    end
  end
end
