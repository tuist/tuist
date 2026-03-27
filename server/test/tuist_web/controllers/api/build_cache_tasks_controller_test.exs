defmodule TuistWeb.API.BuildCacheTasksControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Builds
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.Authentication

  describe "GET /api/projects/:account_handle/:project_handle/xcode/builds/:build_id/cache-tasks" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      conn = Authentication.put_current_user(conn, user)
      %{conn: conn, user: user, project: project}
    end

    test "returns an empty list when there are no cache tasks", %{conn: conn, user: user, project: project} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> build end)

      stub(Builds, :list_cacheable_tasks, fn _attrs ->
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

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/cache-tasks")

      assert %{
               "tasks" => [],
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

    test "returns cache tasks for the build", %{conn: conn, user: user, project: project} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> build end)

      stub(Builds, :list_cacheable_tasks, fn _attrs ->
        {[
           %{
             type: :swift,
             status: :hit_remote,
             key: "abc123",
             read_duration: 250.5,
             write_duration: nil,
             description: "MyModule",
             cas_output_node_ids: ["node1", "node2"]
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

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/cache-tasks")

      response = json_response(conn, 200)
      assert length(response["tasks"]) == 1

      first_task = hd(response["tasks"])
      assert first_task["type"] == "swift"
      assert first_task["status"] == "hit_remote"
      assert first_task["key"] == "abc123"
      assert first_task["read_duration"] == 250.5
      assert first_task["write_duration"] == nil
      assert first_task["description"] == "MyModule"
      assert first_task["cas_output_node_ids"] == ["node1", "node2"]
    end

    test "filters cache tasks by status", %{conn: conn, user: user, project: project} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> build end)

      expect(Builds, :list_cacheable_tasks, fn attrs ->
        assert %{field: :status, op: :==, value: "miss"} in attrs.filters

        {[
           %{
             type: :swift,
             status: :miss,
             key: "abc123",
             read_duration: nil,
             write_duration: 500.0,
             description: nil,
             cas_output_node_ids: []
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
          "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/cache-tasks?status=miss"
        )

      response = json_response(conn, 200)
      assert length(response["tasks"]) == 1
      assert hd(response["tasks"])["status"] == "miss"
    end

    test "filters cache tasks by type", %{conn: conn, user: user, project: project} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> build end)

      expect(Builds, :list_cacheable_tasks, fn attrs ->
        assert %{field: :type, op: :==, value: "clang"} in attrs.filters

        {[
           %{
             type: :clang,
             status: :hit_local,
             key: "def456",
             read_duration: 100.0,
             write_duration: nil,
             description: nil,
             cas_output_node_ids: []
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
          "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/cache-tasks?type=clang"
        )

      response = json_response(conn, 200)
      assert length(response["tasks"]) == 1
      assert hd(response["tasks"])["type"] == "clang"
    end

    test "supports pagination", %{conn: conn, user: user, project: project} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> build end)

      expect(Builds, :list_cacheable_tasks, fn attrs ->
        assert attrs.page == 2
        assert attrs.page_size == 10

        {[
           %{
             type: :swift,
             status: :hit_remote,
             key: "abc123",
             read_duration: 250.5,
             write_duration: nil,
             description: nil,
             cas_output_node_ids: []
           }
         ],
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
          "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/cache-tasks?page=2&page_size=10"
        )

      response = json_response(conn, 200)
      assert length(response["tasks"]) == 1
      assert response["pagination_metadata"]["current_page"] == 2
      assert response["pagination_metadata"]["page_size"] == 10
      assert response["pagination_metadata"]["total_count"] == 11
      assert response["pagination_metadata"]["total_pages"] == 2
    end

    test "returns 404 when build is not found", %{conn: conn, user: user, project: project} do
      stub(Builds, :get_build, fn _id -> nil end)

      conn =
        get(conn, "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{UUIDv7.generate()}/cache-tasks")

      assert %{"message" => "Build not found."} = json_response(conn, 404)
    end

    test "returns 404 when build belongs to a different project", %{conn: conn, user: user, project: project} do
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      {:ok, build} = RunsFixtures.build_fixture(project_id: other_project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> build end)

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/cache-tasks")

      assert %{"message" => "Build not found."} = json_response(conn, 404)
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      conn =
        get(conn, "/api/projects/#{project.account.name}/#{project.name}/xcode/builds/#{UUIDv7.generate()}/cache-tasks")

      assert json_response(conn, :forbidden)
    end
  end
end
