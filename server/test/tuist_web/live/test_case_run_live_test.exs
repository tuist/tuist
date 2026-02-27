defmodule TuistWeb.TestCaseRunLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.Errors.NotFoundError

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

  describe "mount" do
    test "renders test case run page with name and run details", %{
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

    test "raises not found for non-existent test case run", %{
      conn: conn,
      account: account,
      project: project
    } do
      assert_raise NotFoundError, fn ->
        live(
          conn,
          ~p"/#{account.name}/#{project.name}/tests/test-cases/runs/#{UUIDv7.generate()}"
        )
      end
    end

    test "raises not found when test case run belongs to a different project", %{
      conn: conn,
      account: account,
      project: project
    } do
      other_project =
        ProjectsFixtures.project_fixture(name: "other-project", account_id: account.id)

      {:ok, test_run} =
        RunsFixtures.test_fixture(project_id: other_project.id, account_id: account.id)

      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      assert_raise NotFoundError, fn ->
        live(
          conn,
          ~p"/#{account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}"
        )
      end
    end

    test "shows metadata fields in the overview", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: account.id,
          scheme: "AppScheme",
          git_branch: "feature/test",
          git_commit_sha: "abc123def"
        )

      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      {:ok, _lv, html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}")

      assert html =~ "Status"
      assert html =~ "Duration"
      assert html =~ "Ran at"
      assert html =~ "Branch"
      assert html =~ "feature/test"
    end

    test "shows flaky badge when test case run is flaky", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: account.id,
          duration: 2000,
          status: "success",
          macos_version: "14.0",
          xcode_version: "15.0",
          git_branch: "main",
          git_commit_sha: "abc123",
          scheme: "MyScheme",
          ran_at: NaiveDateTime.utc_now(),
          is_ci: true,
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 1000,
              test_cases: [
                %{
                  name: "testFlaky",
                  status: "success",
                  duration: 500,
                  repetitions: [
                    %{repetition_number: 1, name: "First Run", status: "failure", duration: 200},
                    %{repetition_number: 2, name: "Retry", status: "success", duration: 300}
                  ]
                }
              ]
            }
          ]
        })

      RunsFixtures.optimize_test_case_runs()

      test_case_run =
        Tuist.ClickHouseRepo.one!(from(tcr in Tests.TestCaseRun, where: tcr.test_run_id == ^test_run.id))

      {:ok, _lv, html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}")

      assert html =~ "Flaky"
    end
  end
end
