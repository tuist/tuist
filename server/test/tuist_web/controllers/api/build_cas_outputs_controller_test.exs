defmodule TuistWeb.API.BuildCASOutputsControllerTest do
  use TuistTestSupport.Cases.ConnCase, clickhouse: true
  use Mimic

  alias Tuist.Builds
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.Authentication

  describe "GET /api/projects/:account_handle/:project_handle/xcode/builds/:build_id/cas-outputs" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      conn = Authentication.put_current_user(conn, user)
      %{conn: conn, user: user, project: project}
    end

    test "returns an empty list when there are no CAS outputs", %{conn: conn, user: user, project: project} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> {:ok, build} end)

      stub(Builds, :list_cas_outputs, fn _attrs ->
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

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/cas-outputs")

      assert %{
               "outputs" => [],
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

    test "returns CAS outputs for the build", %{conn: conn, user: user, project: project} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> {:ok, build} end)

      stub(Builds, :list_cas_outputs, fn _attrs ->
        {[
           %{
             node_id: "node1",
             checksum: "abc123",
             size: 1024,
             compressed_size: 800,
             duration: 150.5,
             operation: :download,
             type: :swift
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

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/cas-outputs")

      response = json_response(conn, 200)
      assert length(response["outputs"]) == 1

      first_output = hd(response["outputs"])
      assert first_output["node_id"] == "node1"
      assert first_output["checksum"] == "abc123"
      assert first_output["size"] == 1024
      assert first_output["compressed_size"] == 800
      assert first_output["duration"] == 150.5
      assert first_output["operation"] == "download"
      assert first_output["type"] == "swift"
    end

    test "filters CAS outputs by operation", %{conn: conn, user: user, project: project} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> {:ok, build} end)

      expect(Builds, :list_cas_outputs, fn attrs ->
        assert %{field: :operation, op: :==, value: "upload"} in attrs.filters

        {[
           %{
             node_id: "node2",
             checksum: "def456",
             size: 2048,
             compressed_size: 1500,
             duration: 300.0,
             operation: :upload,
             type: :swift
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
          "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/cas-outputs?operation=upload"
        )

      response = json_response(conn, 200)
      assert length(response["outputs"]) == 1
      assert hd(response["outputs"])["operation"] == "upload"
    end

    test "filters CAS outputs by type", %{conn: conn, user: user, project: project} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> {:ok, build} end)

      expect(Builds, :list_cas_outputs, fn attrs ->
        assert %{field: :type, op: :==, value: "swift"} in attrs.filters

        {[
           %{
             node_id: "node1",
             checksum: "abc123",
             size: 1024,
             compressed_size: 800,
             duration: 150.5,
             operation: :download,
             type: :swift
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
          "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/cas-outputs?type=swift"
        )

      response = json_response(conn, 200)
      assert length(response["outputs"]) == 1
      assert hd(response["outputs"])["type"] == "swift"
    end

    test "supports pagination", %{conn: conn, user: user, project: project} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> {:ok, build} end)

      expect(Builds, :list_cas_outputs, fn attrs ->
        assert attrs.page == 2
        assert attrs.page_size == 10

        {[
           %{
             node_id: "node1",
             checksum: "abc123",
             size: 1024,
             compressed_size: 800,
             duration: 150.5,
             operation: :download,
             type: :swift
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
          "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/cas-outputs?page=2&page_size=10"
        )

      response = json_response(conn, 200)
      assert length(response["outputs"]) == 1
      assert response["pagination_metadata"]["current_page"] == 2
      assert response["pagination_metadata"]["page_size"] == 10
      assert response["pagination_metadata"]["total_count"] == 11
      assert response["pagination_metadata"]["total_pages"] == 2
    end

    test "returns 404 when build is not found", %{conn: conn, user: user, project: project} do
      stub(Builds, :get_build, fn _id -> {:error, :not_found} end)

      conn =
        get(conn, "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{UUIDv7.generate()}/cas-outputs")

      assert %{"message" => "Build not found."} = json_response(conn, 404)
    end

    test "returns 404 when build belongs to a different project", %{conn: conn, user: user, project: project} do
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      {:ok, build} = RunsFixtures.build_fixture(project_id: other_project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> {:ok, build} end)

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/cas-outputs")

      assert %{"message" => "Build not found."} = json_response(conn, 404)
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      conn =
        get(conn, "/api/projects/#{project.account.name}/#{project.name}/xcode/builds/#{UUIDv7.generate()}/cas-outputs")

      assert json_response(conn, :forbidden)
    end
  end
end
