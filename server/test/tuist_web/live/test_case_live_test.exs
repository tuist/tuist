defmodule TuistWeb.TestCaseLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "mount with personal account" do
    setup %{conn: conn} do
      # Create a user with a personal account (not an organization)
      user = AccountsFixtures.user_fixture(preload: [:account])
      account = user.account

      # Create a project under the personal account
      project = ProjectsFixtures.project_fixture(name: "my-project", account_id: account.id)

      conn =
        conn
        |> assign(:selected_project, project)
        |> assign(:selected_account, account)
        |> TuistTestSupport.Cases.ConnCase.log_in_user(user)

      %{conn: conn, user: user, account: account, project: project}
    end

    test "renders test case page for personal account", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      # When / Then - page renders without error
      {:ok, _lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_run.test_case_id}")
    end
  end
end
