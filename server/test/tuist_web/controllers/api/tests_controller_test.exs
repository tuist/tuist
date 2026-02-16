defmodule TuistWeb.API.TestsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  describe "POST /api/:account_handle/:project_handle/tests" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "creates a test run with xcode build system by default", %{conn: conn, user: user, project: project} do
      expect(Tests, :get_test, fn _id -> {:error, :not_found} end)

      expect(Tests, :create_test, fn attrs ->
        assert attrs.build_system == "xcode"
        assert attrs.macos_version == "15.0"
        assert attrs.xcode_version == "16.0"
        assert attrs.duration == 5000
        assert attrs.is_ci == false

        {:ok,
         %Tests.Test{
           id: attrs.id,
           duration: attrs.duration,
           project_id: project.id,
           build_system: "xcode"
         }}
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/projects/#{user.account.name}/#{project.name}/tests",
          %{
            duration: 5000,
            macos_version: "15.0",
            xcode_version: "16.0",
            is_ci: false,
            status: "success",
            test_modules: [
              %{
                name: "MyTests",
                status: "success",
                duration: 5000,
                test_suites: [],
                test_cases: [
                  %{name: "test_example", status: "success", duration: 100}
                ]
              }
            ]
          }
        )

      assert %{"type" => "test", "id" => _id} = json_response(conn, 200)
    end

    test "creates a test run with gradle build system", %{conn: conn, user: user, project: project} do
      expect(Tests, :get_test, fn _id -> {:error, :not_found} end)

      expect(Tests, :create_test, fn attrs ->
        assert attrs.build_system == "gradle"
        assert attrs.macos_version == ""
        assert attrs.xcode_version == ""
        assert attrs.scheme == "my-android-app"
        assert attrs.duration == 3000
        assert attrs.is_ci == true

        {:ok,
         %Tests.Test{
           id: attrs.id,
           duration: attrs.duration,
           project_id: project.id,
           build_system: "gradle"
         }}
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/projects/#{user.account.name}/#{project.name}/tests",
          %{
            duration: 3000,
            macos_version: "",
            xcode_version: "",
            is_ci: true,
            build_system: "gradle",
            status: "failure",
            scheme: "my-android-app",
            git_branch: "main",
            git_commit_sha: "abc123",
            test_modules: [
              %{
                name: ":app",
                status: "failure",
                duration: 3000,
                test_suites: [
                  %{name: "com.example.LoginTest", status: "failure", duration: 2000}
                ],
                test_cases: [
                  %{
                    name: "testLogin",
                    test_suite_name: "com.example.LoginTest",
                    status: "failure",
                    duration: 1500,
                    failures: [
                      %{
                        message: "Expected true but was false",
                        path: "LoginTest.kt",
                        line_number: 42,
                        issue_type: "assertion_failure"
                      }
                    ]
                  },
                  %{
                    name: "testLogout",
                    test_suite_name: "com.example.LoginTest",
                    status: "success",
                    duration: 500
                  }
                ]
              }
            ]
          }
        )

      assert %{"type" => "test", "id" => _id} = json_response(conn, 200)
    end

    test "creates a test run without macos_version (not required)", %{conn: conn, user: user, project: project} do
      expect(Tests, :get_test, fn _id -> {:error, :not_found} end)

      expect(Tests, :create_test, fn attrs ->
        assert attrs.build_system == "gradle"
        assert is_nil(attrs.macos_version)

        {:ok,
         %Tests.Test{
           id: attrs.id,
           duration: attrs.duration,
           project_id: project.id,
           build_system: "gradle"
         }}
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/projects/#{user.account.name}/#{project.name}/tests",
          %{
            duration: 1000,
            is_ci: false,
            build_system: "gradle",
            status: "success",
            test_modules: []
          }
        )

      assert %{"type" => "test", "id" => _id} = json_response(conn, 200)
    end
  end
end
