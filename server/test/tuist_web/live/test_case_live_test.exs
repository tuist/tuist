defmodule TuistWeb.TestCaseLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup do
    mark_clickhouse_dirty()
    :ok
  end

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
      {:ok, test_run} = RunsFixtures.test_run_fixture(project_id: project.id, account_id: account.id)
      test_case = RunsFixtures.test_case_fixture(project_id: project.id)
      module_run = RunsFixtures.test_module_run_fixture(test_run_id: test_run.id)

      RunsFixtures.test_case_run_fixture(
        test_run_id: test_run.id,
        test_module_run_id: module_run.id,
        test_case_id: test_case.id,
        project_id: project.id
      )

      # When / Then - page renders without error
      {:ok, _lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case.id}")
    end

    test "quarantine button quarantines a test case", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} = RunsFixtures.test_run_fixture(project_id: project.id, account_id: account.id)
      test_case = RunsFixtures.test_case_fixture(project_id: project.id)
      module_run = RunsFixtures.test_module_run_fixture(test_run_id: test_run.id)

      RunsFixtures.test_case_run_fixture(
        test_run_id: test_run.id,
        test_module_run_id: module_run.id,
        test_case_id: test_case.id,
        project_id: project.id
      )

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case.id}")

      html = lv |> element(~s|button[phx-click="quarantine"]|) |> render_click()

      assert html =~ "Quarantined"
      assert html =~ "Unquarantine"
    end

    test "unquarantine button unquarantines a test case", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} = RunsFixtures.test_run_fixture(project_id: project.id, account_id: account.id)
      test_case = RunsFixtures.test_case_fixture(project_id: project.id)
      module_run = RunsFixtures.test_module_run_fixture(test_run_id: test_run.id)

      RunsFixtures.test_case_run_fixture(
        test_run_id: test_run.id,
        test_module_run_id: module_run.id,
        test_case_id: test_case.id,
        project_id: project.id
      )

      Tuist.Tests.update_test_case(test_case.id, %{is_quarantined: true})

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case.id}")

      html = lv |> element(~s|button[phx-click="unquarantine"]|) |> render_click()

      refute html =~ "Unquarantine"
      assert html =~ ~s|phx-click="quarantine"|
    end
  end
end
