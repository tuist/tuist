defmodule TuistWeb.TestCaseRunLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "mount" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      account = user.account

      project = ProjectsFixtures.project_fixture(name: "my-project", account_id: account.id)

      conn =
        conn
        |> assign(:selected_project, project)
        |> assign(:selected_account, account)
        |> TuistTestSupport.Cases.ConnCase.log_in_user(user)

      %{conn: conn, user: user, account: account, project: project}
    end

    test "renders test case run page", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      {:ok, _lv, html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}")

      assert html =~ test_case_run.name
      assert html =~ "Run Details"
    end

    test "shows link to test case when test_case_id exists", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      {:ok, _lv, html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}")

      assert html =~ "Test Case:"
    end

    test "shows back button linking to test run", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      {:ok, _lv, html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}")

      assert html =~ "test-runs/#{test_case_run.test_run_id}"
    end
  end
end
