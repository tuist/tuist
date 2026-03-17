defmodule TuistWeb.API.BuildIssuesControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Builds
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.Authentication

  describe "GET /api/projects/:account_handle/:project_handle/xcode/builds/:build_id/issues" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      conn = Authentication.put_current_user(conn, user)
      %{conn: conn, user: user, project: project}
    end

    test "returns an empty list when there are no issues", %{conn: conn, user: user, project: project} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> build end)

      stub(Builds, :list_build_issues_paginated, fn _attrs ->
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

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/issues")

      assert %{
               "issues" => [],
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

    test "returns issues for the build", %{conn: conn, user: user, project: project} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> build end)

      stub(Builds, :list_build_issues_paginated, fn _attrs ->
        {[
           %{
             type: :warning,
             target: "MyTarget",
             project: "MyProject",
             title: "Unused variable",
             message: "Variable 'x' is never used",
             signature: "warning:unused-variable",
             step_type: :swift_compilation,
             path: "Sources/MyFile.swift",
             starting_line: 10,
             ending_line: 10,
             starting_column: 5,
             ending_column: 10
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

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/issues")

      response = json_response(conn, 200)
      assert length(response["issues"]) == 1

      first_issue = hd(response["issues"])
      assert first_issue["type"] == "warning"
      assert first_issue["target"] == "MyTarget"
      assert first_issue["project"] == "MyProject"
      assert first_issue["title"] == "Unused variable"
      assert first_issue["message"] == "Variable 'x' is never used"
      assert first_issue["signature"] == "warning:unused-variable"
      assert first_issue["step_type"] == "swift_compilation"
      assert first_issue["path"] == "Sources/MyFile.swift"
      assert first_issue["starting_line"] == 10
      assert first_issue["ending_line"] == 10
      assert first_issue["starting_column"] == 5
      assert first_issue["ending_column"] == 10
    end

    test "filters issues by type", %{conn: conn, user: user, project: project} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> build end)

      expect(Builds, :list_build_issues_paginated, fn attrs ->
        assert %{field: :type, op: :==, value: "error"} in attrs.filters

        {[
           %{
             type: :error,
             target: "MyTarget",
             project: "MyProject",
             title: "Build error",
             message: nil,
             signature: "error:compile",
             step_type: :swift_compilation,
             path: nil,
             starting_line: 0,
             ending_line: 0,
             starting_column: 0,
             ending_column: 0
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
          "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/issues?type=error"
        )

      response = json_response(conn, 200)
      assert length(response["issues"]) == 1
      assert hd(response["issues"])["type"] == "error"
    end

    test "filters issues by target", %{conn: conn, user: user, project: project} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> build end)

      expect(Builds, :list_build_issues_paginated, fn attrs ->
        assert %{field: :target, op: :==, value: "MyTarget"} in attrs.filters

        {[
           %{
             type: :warning,
             target: "MyTarget",
             project: "MyProject",
             title: "Unused variable",
             message: nil,
             signature: "warning:unused",
             step_type: :swift_compilation,
             path: nil,
             starting_line: 0,
             ending_line: 0,
             starting_column: 0,
             ending_column: 0
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
          "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/issues?target=MyTarget"
        )

      response = json_response(conn, 200)
      assert length(response["issues"]) == 1
      assert hd(response["issues"])["target"] == "MyTarget"
    end

    test "supports pagination", %{conn: conn, user: user, project: project} do
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> build end)

      expect(Builds, :list_build_issues_paginated, fn attrs ->
        assert attrs.page == 2
        assert attrs.page_size == 10

        {[
           %{
             type: :warning,
             target: "MyTarget",
             project: "MyProject",
             title: "Unused variable",
             message: nil,
             signature: "warning:unused",
             step_type: :swift_compilation,
             path: nil,
             starting_line: 0,
             ending_line: 0,
             starting_column: 0,
             ending_column: 0
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
          "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/issues?page=2&page_size=10"
        )

      response = json_response(conn, 200)
      assert length(response["issues"]) == 1
      assert response["pagination_metadata"]["current_page"] == 2
      assert response["pagination_metadata"]["page_size"] == 10
      assert response["pagination_metadata"]["total_count"] == 11
      assert response["pagination_metadata"]["total_pages"] == 2
    end

    test "returns 404 when build is not found", %{conn: conn, user: user, project: project} do
      stub(Builds, :get_build, fn _id -> nil end)

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{UUIDv7.generate()}/issues")

      assert %{"message" => "Build not found."} = json_response(conn, 404)
    end

    test "returns 404 when build belongs to a different project", %{conn: conn, user: user, project: project} do
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      {:ok, build} = RunsFixtures.build_fixture(project_id: other_project.id, user_id: user.account.id)

      stub(Builds, :get_build, fn _id -> build end)

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/issues")

      assert %{"message" => "Build not found."} = json_response(conn, 404)
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      conn =
        get(conn, "/api/projects/#{project.account.name}/#{project.name}/xcode/builds/#{UUIDv7.generate()}/issues")

      assert json_response(conn, :forbidden)
    end
  end
end
