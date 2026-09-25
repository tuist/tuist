defmodule TuistWeb.API.NotRunTestsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  alias Tuist.Tests.Enumeration
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)

    {:ok, test} =
      RunsFixtures.test_fixture(
        project_id: project.id,
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 10,
            test_cases: [%{name: "testAdd()", test_suite_name: "MathTests", status: "success", duration: 5}]
          }
        ]
      )

    %{conn: Authentication.put_current_user(conn, user), user: user, project: project, test_run: test}
  end

  defp run_url(user, project, test_run_id, suffix \\ "/not-run-tests"),
    do: "/api/projects/#{user.account.name}/#{project.name}/tests/#{test_run_id}#{suffix}"

  test "lists the candidates the run left out", %{conn: conn, user: user, project: project, test_run: test_run} do
    Enumeration.record(test_run, [
      %{module: "AppTests", suite: "MathTests", name: "testAdd()"},
      %{module: "AppTests", suite: "MathTests", name: "testSubtract()"}
    ])

    response = conn |> get(run_url(user, project, test_run.id)) |> json_response(200)

    assert %{"enumerated_test_count" => 2, "enabled_test_count" => 2, "not_run_test_count" => 1} = response
    assert [%{"module_name" => "AppTests", "suite_name" => "MathTests", "name" => "testSubtract()"}] = response["tests"]

    assert %{"enumerated_test_count" => 2, "not_run_test_count" => 1} =
             conn |> get(run_url(user, project, test_run.id, "")) |> json_response(200)
  end

  test "answers not found when the run's tests were not enumerated", %{
    conn: conn,
    user: user,
    project: project,
    test_run: test_run
  } do
    assert conn |> get(run_url(user, project, test_run.id)) |> json_response(404)

    assert %{"enumerated_test_count" => nil, "not_run_test_count" => nil} =
             conn |> get(run_url(user, project, test_run.id, "")) |> json_response(200)
  end
end
