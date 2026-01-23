defmodule TuistWeb.API.BuildsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.Authentication

  describe "GET /api/projects/:account_handle/:project_handle/builds" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "lists only builds for the project", %{conn: conn, user: user, project: project} do
      {:ok, build_one} =
        RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      {:ok, build_two} =
        RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      {:ok, _other_project_build} = RunsFixtures.build_fixture()

      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/builds?page_size=1"
        )

      response = json_response(conn, :ok)

      assert length(response["builds"]) == 1
      assert hd(response["builds"])["id"] in [build_one.id, build_two.id]
    end

    test "returns forbidden response when the user doesn't have access to the project", %{conn: conn} do
      another_user = AccountsFixtures.user_fixture(preload: [:account])
      another_project = ProjectsFixtures.project_fixture(account_id: another_user.account.id)

      conn =
        get(conn, "/api/projects/#{another_user.account.name}/#{another_project.name}/builds")

      assert response(conn, :forbidden)
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/builds/:build_id" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "shows a build", %{conn: conn, user: user, project: project} do
      {:ok, build} =
        RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/builds/#{build.id}"
        )

      response = json_response(conn, :ok)
      assert response["id"] == build.id
    end

    test "returns not found when the build isn't in the project", %{conn: conn, user: user, project: project} do
      {:ok, other_build} = RunsFixtures.build_fixture()

      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/builds/#{other_build.id}"
        )

      assert response(conn, :not_found)
    end
  end
end
