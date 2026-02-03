defmodule TuistWeb.API.BuildsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Runs
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

    test "returns an empty list when there are no builds", %{conn: conn, user: user, project: project} do
      stub(Runs, :list_build_runs, fn _attrs, _opts ->
        {[],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 0,
           total_pages: 0
         }}
      end)

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/builds")

      assert %{
               "builds" => [],
               "pagination_metadata" => %{
                 "has_next_page" => false,
                 "has_previous_page" => false,
                 "current_page" => 1,
                 "page_size" => 20,
                 "total_count" => 0,
                 "total_pages" => 0
               }
             } = json_response(conn, 200)
    end

    test "returns builds for the project", %{conn: conn, user: user, project: project} do
      {:ok, build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: user.account.id,
          status: :success,
          duration: 5000,
          scheme: "MyApp",
          configuration: "Debug"
        )

      stub(Runs, :list_build_runs, fn _attrs, _opts ->
        {[build],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 1,
           total_pages: 1
         }}
      end)

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/builds")

      response = json_response(conn, 200)
      assert length(response["builds"]) == 1

      first_build = hd(response["builds"])
      assert first_build["id"] == build.id
      assert first_build["status"] == "success"
      assert first_build["duration"] == 5000
      assert first_build["scheme"] == "MyApp"
      assert first_build["configuration"] == "Debug"
      assert first_build["cacheable_tasks_count"] == build.cacheable_tasks_count
      assert first_build["cacheable_task_local_hits_count"] == build.cacheable_task_local_hits_count
      assert first_build["cacheable_task_remote_hits_count"] == build.cacheable_task_remote_hits_count
    end

    test "filters builds by status", %{conn: conn, user: user, project: project} do
      {:ok, failure_build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: user.account.id,
          status: :failure,
          duration: 3000
        )

      expect(Runs, :list_build_runs, fn attrs, _opts ->
        assert %{field: :status, op: :==, value: :failure} in attrs.filters

        {[failure_build],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 1,
           total_pages: 1
         }}
      end)

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/builds?status=failure")

      response = json_response(conn, 200)
      assert length(response["builds"]) == 1
      assert hd(response["builds"])["status"] == "failure"
    end

    test "supports pagination", %{conn: conn, user: user, project: project} do
      {:ok, build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: user.account.id
        )

      expect(Runs, :list_build_runs, fn attrs, _opts ->
        assert attrs.page == 2
        assert attrs.page_size == 10

        {[build],
         %{
           has_next_page?: false,
           has_previous_page?: true,
           current_page: 2,
           page_size: 10,
           total_count: 11,
           total_pages: 2
         }}
      end)

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/builds?page=2&page_size=10")

      response = json_response(conn, 200)
      assert length(response["builds"]) == 1
      assert response["pagination_metadata"]["current_page"] == 2
      assert response["pagination_metadata"]["page_size"] == 10
      assert response["pagination_metadata"]["total_count"] == 11
      assert response["pagination_metadata"]["total_pages"] == 2
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      conn = get(conn, "/api/projects/#{project.account.name}/#{project.name}/builds")

      assert json_response(conn, :forbidden)
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/builds/:build_id" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "returns a build by ID", %{conn: conn, user: user, project: project} do
      {:ok, build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: user.account.id,
          status: :success,
          duration: 5000,
          scheme: "MyApp",
          configuration: "Release",
          xcode_version: "15.0",
          macos_version: "14.0",
          cacheable_tasks_count: 10,
          cacheable_task_local_hits_count: 3,
          cacheable_task_remote_hits_count: 5
        )

      stub(Runs, :get_build, fn _id ->
        build
      end)

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/builds/#{build.id}")

      response = json_response(conn, 200)
      assert response["id"] == build.id
      assert response["status"] == "success"
      assert response["duration"] == 5000
      assert response["scheme"] == "MyApp"
      assert response["configuration"] == "Release"
      assert response["xcode_version"] == "15.0"
      assert response["macos_version"] == "14.0"
      assert response["cacheable_tasks_count"] == 10
      assert response["cacheable_task_local_hits_count"] == 3
      assert response["cacheable_task_remote_hits_count"] == 5
    end

    test "returns 404 when build is not found", %{conn: conn, user: user, project: project} do
      stub(Runs, :get_build, fn _id ->
        nil
      end)

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/builds/#{UUIDv7.generate()}")

      assert %{"message" => "Build not found."} = json_response(conn, 404)
    end

    test "returns 404 when build belongs to a different project", %{conn: conn, user: user, project: project} do
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      {:ok, build} =
        RunsFixtures.build_fixture(
          project_id: other_project.id,
          user_id: user.account.id
        )

      stub(Runs, :get_build, fn _id ->
        build
      end)

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/builds/#{build.id}")

      assert %{"message" => "Build not found."} = json_response(conn, 404)
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      conn = get(conn, "/api/projects/#{project.account.name}/#{project.name}/builds/#{UUIDv7.generate()}")

      assert json_response(conn, :forbidden)
    end
  end
end
