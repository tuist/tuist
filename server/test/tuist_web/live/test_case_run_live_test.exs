defmodule TuistWeb.TestCaseRunLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Tuist.Storage
  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.Errors.NotFoundError

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    account = user.account

    project = ProjectsFixtures.project_fixture(name: "my-project", account_id: account.id)

    stub(Storage, :generate_download_url, fn _key, _account, _opts -> "https://s3.example.com/download" end)

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

  describe "parameterized test arguments" do
    test "shows Arguments card when test case run has arguments", %{
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
          status: "failure",
          macos_version: "14.0",
          xcode_version: "15.0",
          git_branch: "main",
          git_commit_sha: "abc123",
          ran_at: NaiveDateTime.utc_now(),
          is_ci: false,
          test_modules: [
            %{
              name: "TestModule",
              status: "failure",
              duration: 2000,
              test_cases: [
                %{
                  name: "parameterized(value:)",
                  test_suite_name: "Suite",
                  status: "failure",
                  duration: 1000,
                  arguments: [
                    %{name: ".hello", status: "success", duration: 400},
                    %{
                      name: ".failing",
                      status: "failure",
                      duration: 600,
                      failures: [
                        %{message: "Expected true", path: "Test.swift", line_number: 10, issue_type: "assertion_failure"}
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        })

      RunsFixtures.optimize_test_case_runs()

      test_case_run =
        Tuist.ClickHouseRepo.one!(from(tcr in Tests.TestCaseRun, where: tcr.test_run_id == ^test_run.id))

      {:ok, lv, html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}")

      assert has_element?(lv, "[data-part='arguments-card']")
      assert html =~ ".hello"
      assert html =~ ".failing"
      assert html =~ "Passed"
      assert html =~ "Failed"
    end

    test "does not show Arguments card for non-parameterized tests", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}")

      refute has_element?(lv, "[data-part='arguments-card']")
    end

    test "shows failures grouped by argument when arguments have failures", %{
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
          status: "failure",
          macos_version: "14.0",
          xcode_version: "15.0",
          git_branch: "main",
          git_commit_sha: "abc123",
          ran_at: NaiveDateTime.utc_now(),
          is_ci: false,
          test_modules: [
            %{
              name: "TestModule",
              status: "failure",
              duration: 2000,
              test_cases: [
                %{
                  name: "paramTest(input:)",
                  test_suite_name: "Suite",
                  status: "failure",
                  duration: 1000,
                  arguments: [
                    %{
                      name: ".variant1",
                      status: "failure",
                      duration: 500,
                      failures: [
                        %{
                          message: "Assertion failed in variant1",
                          path: "Test.swift",
                          line_number: 10,
                          issue_type: "assertion_failure"
                        }
                      ]
                    },
                    %{name: ".variant2", status: "success", duration: 500}
                  ]
                }
              ]
            }
          ]
        })

      RunsFixtures.optimize_test_case_runs()

      test_case_run =
        Tuist.ClickHouseRepo.one!(from(tcr in Tests.TestCaseRun, where: tcr.test_run_id == ^test_run.id))

      {:ok, lv, html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}")

      assert has_element?(lv, "[data-part='failures-list']")
      assert html =~ ".variant1"
      assert html =~ "Assertion failed in variant1"
    end
  end

  describe "attachments" do
    test "shows Attachments card when test case run has image attachments", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      RunsFixtures.test_case_run_attachment_fixture(
        test_case_run_id: test_case_run.id,
        file_name: "screenshot.png"
      )

      {:ok, lv, html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}")

      assert has_element?(lv, "[data-part='attachments-card']")
      assert html =~ "Attachments"
      assert html =~ "screenshot.png"
    end

    test "shows Attachments card with text file attachments", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      RunsFixtures.test_case_run_attachment_fixture(
        test_case_run_id: test_case_run.id,
        file_name: "output.log"
      )

      {:ok, _lv, html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}")

      assert html =~ "Attachments"
      assert html =~ "output.log"
    end

    test "does not show Attachments card when only attachment is crash report", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      RunsFixtures.crash_report_fixture(test_case_run_id: test_case_run.id)

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}")

      refute has_element?(lv, "[data-part='attachments-card']")
    end

    test "shows Image type badge for image attachments", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      RunsFixtures.test_case_run_attachment_fixture(
        test_case_run_id: test_case_run.id,
        file_name: "screenshot.png"
      )

      {:ok, _lv, html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}")

      assert html =~ "Image"
    end

    test "shows Text File type badge for text attachments", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      RunsFixtures.test_case_run_attachment_fixture(
        test_case_run_id: test_case_run.id,
        file_name: "debug.txt"
      )

      {:ok, _lv, html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/runs/#{test_case_run.id}")

      assert html =~ "Text File"
    end
  end
end
