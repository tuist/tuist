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

    test "scopes test case runs to the selected project", %{
      conn: conn,
      account: account,
      project: project
    } do
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      expect(Tuist.Tests, :list_test_case_runs, 2, fn attrs ->
        assert %{field: :project_id, op: :==, value: project.id} in attrs.filters
        assert %{field: :test_case_id, op: :==, value: test_case_run.test_case_id} in attrs.filters

        Mimic.call_original(Tuist.Tests, :list_test_case_runs, [attrs])
      end)

      {:ok, _lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_run.test_case_id}")
    end

    test "scopes the summary widgets to the last 30 days by default", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given - one run today, one three days ago, and one outside the default window
      test_case_id = seed_runs_across_time(project)

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}")

      render_async(lv)

      # Then - the run from 40 days ago is excluded
      assert widget_value(lv, "widget-test-case-runs") == "2"
    end

    test "scopes the summary widgets to the selected period", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given
      test_case_id = seed_runs_across_time(project)

      # When
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}?analytics-date-range=last-24-hours"
        )

      render_async(lv)

      # Then - only the run from today falls inside the period
      assert widget_value(lv, "widget-test-case-runs") == "1"
    end

    test "renders the reliability widget as empty when no runs fall in the period", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given
      test_case_id = seed_runs_across_time(project)

      query =
        URI.encode_query(%{
          "analytics-date-range" => "custom",
          "analytics-start-date" => "2020-01-01T00:00:00Z",
          "analytics-end-date" => "2020-01-31T00:00:00Z"
        })

      # When
      {:ok, lv, _html} =
        live(conn, "/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}?#{query}")

      render_async(lv)

      # Then
      assert has_element?(lv, "#widget-test-reliability[data-empty='true']")
      assert has_element?(lv, "#widget-flakiness-rate[data-empty='true']")
    end

    test "keeps the flakiness widget in place when no runs were flaky", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given - runs exist in the period, none of them flaky
      test_case_id = seed_runs_across_time(project)

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}")

      render_async(lv)

      # Then - 0% is an answer, so the tile stays rather than dropping out of the row
      assert widget_value(lv, "widget-flakiness-rate") == "0.0%"
      refute has_element?(lv, "#widget-flakiness-rate[data-empty='true']")
    end

    test "changing the period patches the date range into the query", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given
      test_case_id = seed_runs_across_time(project)

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}")

      render_async(lv)

      # When
      render_hook(lv, "analytics_period_changed", %{
        "value" => %{"start" => "2024-04-01", "end" => "2024-04-30"},
        "preset" => "last-7-days"
      })

      render_async(lv)

      # Then
      assert_patched(
        lv,
        ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}?analytics-date-range=last-7-days"
      )

      assert widget_value(lv, "widget-test-case-runs") == "2"
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

  defp seed_runs_across_time(project) do
    {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)
    test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
    [test_case_run | _] = test_run.test_case_runs

    for days_ago <- [3, 40] do
      ran_at = DateTime.utc_now() |> DateTime.add(-days_ago, :day) |> DateTime.to_naive()

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_run.test_case_id,
        ran_at: ran_at,
        inserted_at: ran_at
      )
    end

    test_case_run.test_case_id
  end

  defp widget_value(lv, widget_id) do
    lv
    |> element("##{widget_id} [data-part='value']")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> String.trim()
  end
end
