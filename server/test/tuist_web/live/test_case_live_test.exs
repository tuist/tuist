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

    test "muting a test case via set-state", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_run.test_case_id}")

      html = render_hook(lv, "set-state", %{"data" => "muted"})

      assert html =~ "Quarantined"

      {:ok, fetched} = Tuist.Tests.get_test_case_by_id(test_case_run.test_case_id)
      assert fetched.state == "muted"
    end

    test "mark as flaky button marks a test case as flaky", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_run.test_case_id}")

      html = lv |> element(~s|button[phx-click="mark-as-flaky"]|) |> render_click()

      assert html =~ "Unmark as flaky"

      {:ok, fetched} = Tuist.Tests.get_test_case_by_id(test_case_run.test_case_id)
      assert fetched.is_flaky == true
    end

    test "unmark as flaky button unmarks a test case as flaky", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      Tuist.Tests.update_test_case(test_case_run.test_case_id, %{is_flaky: true})

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_run.test_case_id}")

      html = lv |> element(~s|button[phx-click="unmark-as-flaky"]|) |> render_click()

      assert html =~ "Mark as flaky"

      {:ok, fetched} = Tuist.Tests.get_test_case_by_id(test_case_run.test_case_id)
      assert fetched.is_flaky == false
    end

    test "unmuting a test case via set-state", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      Tuist.Tests.update_test_case(test_case_run.test_case_id, %{state: "muted"})

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_run.test_case_id}")

      render_hook(lv, "set-state", %{"data" => "enabled"})

      {:ok, fetched} = Tuist.Tests.get_test_case_by_id(test_case_run.test_case_id)
      assert fetched.state == "enabled"
    end
  end
end
