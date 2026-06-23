defmodule TuistWeb.TestCaseLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
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

    test "flaky-runs tab renders a module-hash group for cross-commit flakiness", %{
      conn: conn,
      account: account,
      project: project
    } do
      hash = "hash-#{System.unique_integer([:positive])}"
      seed_hash_flaky_run(project, account, "commit-a-#{System.unique_integer([:positive])}", "success", hash)
      seed_hash_flaky_run(project, account, "commit-b-#{System.unique_integer([:positive])}", "failure", hash)

      RunsFixtures.optimize_test_case_runs()
      {[test_case], _} = Tuist.Tests.list_test_cases(project.id, %{})

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case.id}?tab=flaky-runs")

      html = render_async(lv)
      assert html =~ "Module hash"
      assert html =~ "Same module hash across"
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

      assert html =~ "Muted"

      {:ok, fetched} = Tuist.Tests.get_test_case_by_id(test_case_run.test_case_id)
      assert fetched.state == "muted"
    end

    test "skipping a test case via set-state", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_run.test_case_id}")

      html = render_hook(lv, "set-state", %{"data" => "skipped"})

      assert html =~ "Skipped"

      {:ok, fetched} = Tuist.Tests.get_test_case_by_id(test_case_run.test_case_id)
      assert fetched.state == "skipped"
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

    test "shows exact event dates in overview and history tooltips", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      inserted_at = ~N[2024-01-15 14:30:25.000000]

      event =
        RunsFixtures.test_case_event_fixture(
          test_case_id: test_case_run.test_case_id,
          event_type: "skipped",
          inserted_at: inserted_at
        )

      conn =
        conn
        |> put_req_cookie("user_timezone", "America/New_York")
        |> put_session("user_timezone", "America/New_York")

      {:ok, _lv, overview_html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_run.test_case_id}")

      assert overview_html =~ "overview-history-event-#{event.id}-time-tooltip"
      assert overview_html =~ "Mon 15 Jan 2024 at 09:30"

      {:ok, _lv, history_html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_run.test_case_id}?tab=history")

      assert history_html =~ "test-history-event-#{event.id}-time-tooltip"
      assert history_html =~ "Mon 15 Jan 2024 at 09:30"
    end
  end

  defp seed_hash_flaky_run(project, account, commit_sha, status, hash) do
    {:ok, test} =
      RunsFixtures.test_fixture(
        project_id: project.id,
        account_id: account.id,
        git_commit_sha: commit_sha,
        is_ci: true,
        status: status,
        test_modules: [
          %{
            name: "TestModule",
            status: status,
            duration: 500,
            test_cases: [%{name: "flakyTest", status: status, duration: 250}]
          }
        ]
      )

    command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        test_run_id: test.id,
        name: "test",
        is_ci: true
      )

    with_flushed_ingestion_buffers(fn ->
      Tuist.Xcode.create_xcode_graph(%{
        command_event: command_event,
        xcode_graph: %{
          name: "Graph",
          projects: [
            %{
              "name" => "App",
              "path" => "App",
              "targets" => [
                %{"name" => "TestModule", "selective_testing_metadata" => %{"hash" => hash, "hit" => "remote"}}
              ]
            }
          ]
        }
      })
    end)

    RunsFixtures.optimize_test_case_runs()
    Tuist.Tests.detect_flaky_tests_by_hash(command_event, test.id)
    test
  end
end
