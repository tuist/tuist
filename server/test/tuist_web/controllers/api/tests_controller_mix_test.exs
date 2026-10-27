defmodule TuistWeb.API.TestsControllerMixTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Tests
  alias Tuist.Tests.Test
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  describe "POST /api/:account_handle/:project_handle/tests" do
    setup %{conn: conn} do
      stub(Tuist.VCS, :enqueue_vcs_pull_request_comment, fn _ -> :ok end)
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      %{conn: Authentication.put_current_user(conn, user), user: user, project: project}
    end

    test "creates a test run with the elixir build system and accepts contract_version", %{
      conn: conn,
      user: user,
      project: project
    } do
      expect(Tests, :get_test, fn _id, _opts -> {:error, :not_found} end)

      expect(Tests, :create_test, fn attrs ->
        assert attrs.build_system == "mix"
        assert attrs.duration == 4200
        assert attrs.is_ci == true

        {:ok,
         %Test{
           id: attrs.id,
           duration: attrs.duration,
           project_id: project.id,
           build_system: "mix",
           test_case_runs: []
         }}
      end)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/projects/#{user.account.name}/#{project.name}/tests",
          %{
            contract_version: "0.1",
            build_system: "mix",
            duration: 4200,
            is_ci: true,
            status: "success",
            test_modules: [
              %{
                name: "GreeterTest",
                status: "success",
                duration: 4200,
                test_suites: [],
                test_cases: [
                  %{name: "test greets the world", status: "success", duration: 42}
                ]
              }
            ]
          }
        )

      assert %{"type" => "test", "id" => _id} = json_response(conn, 200)
    end
  end
end
