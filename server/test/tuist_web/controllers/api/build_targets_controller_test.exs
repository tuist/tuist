defmodule TuistWeb.API.BuildTargetsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Builds
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.Authentication

  describe "GET /api/projects/:account_handle/:project_handle/xcode/builds/:build_id/targets" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      conn = Authentication.put_current_user(conn, user)
      %{conn: conn, user: user, project: project}
    end

    test "returns an empty list when there are no targets", %{conn: conn, user: user, project: project} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> {:ok, build} end)

      stub(Builds, :list_build_targets, fn _attrs ->
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

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/targets")

      assert %{
               "targets" => [],
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

    test "returns targets for the build", %{conn: conn, user: user, project: project} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> {:ok, build} end)

      stub(Builds, :list_build_targets, fn _attrs ->
        {[
           %{
             name: "MyTarget",
             project: "MyProject",
             build_duration: 5000,
             compilation_duration: 3000,
             status: :success
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 1,
           total_pages: 1
         }}
      end)

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/targets")

      response = json_response(conn, 200)
      assert length(response["targets"]) == 1

      first_target = hd(response["targets"])
      assert first_target["name"] == "MyTarget"
      assert first_target["project"] == "MyProject"
      assert first_target["build_duration"] == 5000
      assert first_target["compilation_duration"] == 3000
      assert first_target["status"] == "success"
    end

    test "filters targets by status", %{conn: conn, user: user, project: project} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> {:ok, build} end)

      expect(Builds, :list_build_targets, fn attrs ->
        assert %{field: :status, op: :==, value: "failure"} in attrs.filters

        {[
           %{
             name: "FailingTarget",
             project: "MyProject",
             build_duration: 2000,
             compilation_duration: 1000,
             status: :failure
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 1,
           total_pages: 1
         }}
      end)

      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/targets?status=failure"
        )

      response = json_response(conn, 200)
      assert length(response["targets"]) == 1
      assert hd(response["targets"])["status"] == "failure"
    end

    test "supports pagination", %{conn: conn, user: user, project: project} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> {:ok, build} end)

      expect(Builds, :list_build_targets, fn attrs ->
        assert attrs.page == 2
        assert attrs.page_size == 10

        {[%{name: "MyTarget", project: "MyProject", build_duration: 5000, compilation_duration: 3000, status: :success}],
         %{
           has_next_page?: false,
           has_previous_page?: true,
           current_page: 2,
           page_size: 10,
           total_count: 11,
           total_pages: 2
         }}
      end)

      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/targets?page=2&page_size=10"
        )

      response = json_response(conn, 200)
      assert length(response["targets"]) == 1
      assert response["pagination_metadata"]["current_page"] == 2
      assert response["pagination_metadata"]["page_size"] == 10
      assert response["pagination_metadata"]["total_count"] == 11
      assert response["pagination_metadata"]["total_pages"] == 2
    end

    test "returns 404 when build is not found", %{conn: conn, user: user, project: project} do
      stub(Builds, :get_build, fn _id -> {:error, :not_found} end)

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{UUIDv7.generate()}/targets")

      assert %{"message" => "Build not found."} = json_response(conn, 404)
    end

    test "returns 404 when build belongs to a different project", %{conn: conn, user: user, project: project} do
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      {:ok, build} = RunsFixtures.build_fixture(project_id: other_project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> {:ok, build} end)

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/targets")

      assert %{"message" => "Build not found."} = json_response(conn, 404)
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      conn =
        get(conn, "/api/projects/#{project.account.name}/#{project.name}/xcode/builds/#{UUIDv7.generate()}/targets")

      assert json_response(conn, :forbidden)
    end
  end
end
