defmodule TuistWeb.API.BuildsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Builds
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
      stub(Builds, :list_build_runs, fn _attrs, _opts ->
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

      stub(Builds, :list_build_runs, fn _attrs, _opts ->
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

      expect(Builds, :list_build_runs, fn attrs, _opts ->
        assert %{field: :status, op: :==, value: "failure"} in attrs.filters

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

      expect(Builds, :list_build_runs, fn attrs, _opts ->
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

    test "returns custom_metadata in response", %{conn: conn, user: user, project: project} do
      {:ok, build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: user.account.id,
          custom_tags: ["nightly", "release"],
          custom_values: %{"ticket" => "PROJ-1234"}
        )

      stub(Builds, :list_build_runs, fn _attrs, _opts ->
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
      first_build = hd(response["builds"])
      assert first_build["custom_metadata"]["tags"] == ["nightly", "release"]
      assert first_build["custom_metadata"]["values"] == %{"ticket" => "PROJ-1234"}
    end

    test "filters builds by tags", %{conn: conn, user: user, project: project} do
      {:ok, tagged_build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: user.account.id,
          custom_tags: ["nightly", "release"]
        )

      expect(Builds, :list_build_runs, fn attrs, _opts ->
        assert %{field: :custom_tags, op: :contains, value: "nightly"} in attrs.filters

        {[tagged_build],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 1,
           total_pages: 1
         }}
      end)

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/builds?tags[]=nightly")

      response = json_response(conn, 200)
      assert length(response["builds"]) == 1
    end

    test "filters builds by multiple tags", %{conn: conn, user: user, project: project} do
      {:ok, tagged_build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: user.account.id,
          custom_tags: ["nightly", "release"]
        )

      expect(Builds, :list_build_runs, fn attrs, _opts ->
        assert %{field: :custom_tags, op: :contains, value: "nightly"} in attrs.filters
        assert %{field: :custom_tags, op: :contains, value: "release"} in attrs.filters

        {[tagged_build],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 1,
           total_pages: 1
         }}
      end)

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/builds?tags[]=nightly&tags[]=release")

      response = json_response(conn, 200)
      assert length(response["builds"]) == 1
    end

    test "filters builds by custom values", %{conn: conn, user: user, project: project} do
      {:ok, build_with_values} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: user.account.id,
          custom_values: %{"ticket" => "PROJ-1234", "runner" => "macos-14"}
        )

      expect(Builds, :list_build_runs, fn _attrs, opts ->
        assert Keyword.get(opts, :custom_values) == %{"ticket" => "PROJ-1234"}

        {[build_with_values],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           current_page: 1,
           page_size: 20,
           total_count: 1,
           total_pages: 1
         }}
      end)

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/builds?values[]=ticket:PROJ-1234")

      response = json_response(conn, 200)
      assert length(response["builds"]) == 1
    end

    test "filters builds by multiple custom values", %{conn: conn, user: user, project: project} do
      {:ok, build_with_values} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: user.account.id,
          custom_values: %{"ticket" => "PROJ-1234", "runner" => "macos-14"}
        )

      expect(Builds, :list_build_runs, fn _attrs, opts ->
        assert Keyword.get(opts, :custom_values) == %{"ticket" => "PROJ-1234", "runner" => "macos-14"}

        {[build_with_values],
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
          "/api/projects/#{user.account.name}/#{project.name}/builds?values[]=ticket:PROJ-1234&values[]=runner:macos-14"
        )

      response = json_response(conn, 200)
      assert length(response["builds"]) == 1
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

      stub(Builds, :get_build, fn _id ->
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
      stub(Builds, :get_build, fn _id ->
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

      stub(Builds, :get_build, fn _id ->
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

    test "returns custom_metadata in response", %{conn: conn, user: user, project: project} do
      {:ok, build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: user.account.id,
          custom_tags: ["nightly", "staging"],
          custom_values: %{"runner" => "macos-14", "jira" => "https://jira.example.com/PROJ-123"}
        )

      stub(Builds, :get_build, fn _id ->
        build
      end)

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/builds/#{build.id}")

      response = json_response(conn, 200)
      assert response["custom_metadata"]["tags"] == ["nightly", "staging"]

      assert response["custom_metadata"]["values"] == %{
               "runner" => "macos-14",
               "jira" => "https://jira.example.com/PROJ-123"
             }
    end
  end
end
