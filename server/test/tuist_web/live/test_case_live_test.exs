defmodule TuistWeb.TestCaseLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Tests
  alias TuistTestSupport.Cases.ConnCase
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
        |> ConnCase.log_in_user(user)

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

      expect(Tests, :list_test_case_runs, 2, fn attrs ->
        assert %{field: :project_id, op: :==, value: project.id} in attrs.filters
        assert %{field: :test_case_id, op: :==, value: test_case_run.test_case_id} in attrs.filters

        Mimic.call_original(Tests, :list_test_case_runs, [attrs])
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

    test "charts the duration of the test case over the selected period", %{
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
          ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}?analytics-selected-widget=duration"
        )

      render_async(lv)

      # Then - the distribution is on the chart, not only in the widget above it
      option = chart_option(lv, "test-case-duration-chart")

      assert Enum.map(option["series"], & &1["name"]) == ["Average", "p99", "p90", "p50"]
    end

    test "breaks the chart line over a day the test case did not run", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given - runs today and three days ago, nothing in between
      test_case_id = seed_runs_across_time(project)

      # When
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}?analytics-selected-widget=duration"
        )

      render_async(lv)

      # Then - the empty days are gaps, not runs that took no time
      [average | _] = chart_option(lv, "test-case-duration-chart")["series"]
      values = Enum.map(average["data"], &point_value/1)

      assert Enum.any?(values, &is_nil/1)
      refute 0 in values
    end

    test "spans the days it did not run and points the ones it did", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given - runs today and three days ago, with empty days between them
      test_case_id = seed_runs_across_time(project)

      # When
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}?analytics-selected-widget=duration"
        )

      render_async(lv)

      # Then - one line across the window, with a symbol on each measured day so
      # the stretches it spans are not mistaken for observations
      [average | _] = chart_option(lv, "test-case-duration-chart")["series"]

      {measured, empty} = Enum.split_with(average["data"], &(not is_nil(point_value(&1))))

      assert average["connectNulls"] == true
      # A series that draws no symbol at all would make the sizes below inert
      assert average["symbol"] == "circle"
      assert Enum.any?(measured)
      assert Enum.all?(measured, &(&1["symbolSize"] > 0))
      assert Enum.all?(empty, &(&1["symbolSize"] == 0))
    end

    test "leaves a series that measured every day bare, so it reads as a plain line", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given - a window whose every day holds runs, so the line spans nothing
      test_case_id = seed_consecutive_runs(project)

      # A span of one day buckets hourly, so the window covers three whole days
      query =
        URI.encode_query(%{
          "analytics-selected-widget" => "duration",
          "analytics-date-range" => "custom",
          "analytics-start-date" => start_of_day_ago(3),
          "analytics-end-date" => end_of_day_ago(1)
        })

      # When
      {:ok, lv, _html} =
        live(conn, "/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}?#{query}")

      render_async(lv)

      # Then - nothing to disambiguate, so no symbols
      [average | _] = chart_option(lv, "test-case-duration-chart")["series"]

      refute Enum.any?(average["data"], &is_nil(point_value(&1)))
      assert Enum.all?(average["data"], &(&1["symbolSize"] == 0))
    end

    test "replaces the duration chart with an empty state when the period holds no runs", %{
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
      refute has_element?(lv, "#test-case-duration-chart")
      refute has_element?(lv, "#test-case-runs-chart")
      assert has_element?(lv, "[data-part='analytics'] [data-empty]")
    end

    test "counts failed or flaky runs when the widget's dropdown picks them", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given - a window holding one run of every outcome
      test_case_id = seed_runs_of_every_outcome(project)

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}")

      render_async(lv)

      # Then - the widget opens on every run
      assert widget_value(lv, "widget-test-case-runs") == "6"

      # When
      render_hook(lv, "select_runs_type", %{"type" => "failed"})

      # Then
      assert widget_value(lv, "widget-test-case-runs") == "1"
      assert render(lv) =~ "Failed test case runs"

      # When
      render_hook(lv, "select_runs_type", %{"type" => "flaky"})

      # Then
      assert widget_value(lv, "widget-test-case-runs") == "1"
      assert render(lv) =~ "Flaky test case runs"
    end

    test "counts the same runs the bar segment it names does", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given - a run that is failed and flaky at once, which the bar files under
      # Flaky, plus one plainly failed run
      test_case_run = passing_test_case_run(project)
      ran_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.to_naive()

      for {status, is_flaky} <- [{1, true}, {1, false}] do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_run.test_case_id,
          status: status,
          is_flaky: is_flaky,
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_run.test_case_id}")

      render_async(lv)

      # When
      render_hook(lv, "select_widget", %{"widget" => "test_case_runs"})
      render_hook(lv, "select_runs_type", %{"type" => "failed"})

      # Then - the widget cannot report runs the chart draws somewhere else
      segments = chart_option(lv, "test-case-runs-chart")["series"]
      failed = Enum.find(segments, &(&1["name"] == "Failed"))
      drawn = failed["data"] |> Enum.map(&segment_count/1) |> Enum.sum()

      assert widget_value(lv, "widget-test-case-runs") == "#{drawn}"
      assert drawn == 1
    end

    test "counting a run type pulls the card back to the runs chart", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given - another widget's chart is on screen
      test_case_id = seed_runs_across_time(project)

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}?analytics-selected-widget=reliability"
        )

      render_async(lv)

      # When
      render_hook(lv, "select_runs_type", %{"type" => "failed"})

      # Then
      assert has_element?(lv, "#test-case-runs-chart")
      refute has_element?(lv, "#test-case-analytics-chart")
    end

    test "compares each widget against the window before it", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given - two runs in the last week, one in the week before it
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      test_case_run = Enum.find(test_run.test_case_runs, &(&1.name == "testExample"))

      for days_ago <- [1, 2, 9] do
        ran_at = DateTime.utc_now() |> DateTime.add(-days_ago, :day) |> DateTime.to_naive()

        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_run.test_case_id,
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      # When
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_run.test_case_id}?analytics-date-range=last-7-days"
        )

      render_async(lv)

      # Then - three runs this week against one the week before
      assert widget_trend(lv, "widget-test-case-runs") =~ "+200.0%"
      assert widget_trend(lv, "widget-test-case-runs") =~ "since last week"
    end

    test "counts a run on the window boundary once, not in both windows", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given - one run before the window, one exactly on its first instant, and
      # one inside it
      test_case_run = passing_test_case_run(project)

      for ran_at <- [
            ~N[2024-04-27 12:00:00.000000],
            ~N[2024-04-28 00:00:00.000000],
            ~N[2024-04-29 12:00:00.000000]
          ] do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_run.test_case_id,
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      query =
        URI.encode_query(%{
          "analytics-date-range" => "custom",
          "analytics-start-date" => "2024-04-28T00:00:00Z",
          "analytics-end-date" => "2024-04-30T00:00:00Z"
        })

      # When
      {:ok, lv, _html} =
        live(conn, "/#{account.name}/#{project.name}/tests/test-cases/#{test_case_run.test_case_id}?#{query}")

      render_async(lv)

      # Then - two runs this window against one before it. Counting the boundary
      # run in both would read as two against two, and no change at all.
      assert widget_value(lv, "widget-test-case-runs") == "2"
      assert widget_trend(lv, "widget-test-case-runs") =~ "+100.0%"
    end

    test "leaves a widget without a trend when the window before it was empty", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given - runs in this window only
      test_case_id = seed_runs_across_time(project)

      # When
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}?analytics-date-range=last-24-hours"
        )

      render_async(lv)

      # Then - a jump from nothing is not a percentage
      refute has_element?(lv, "#widget-test-case-runs [data-part='trend'] .noora-badge")
    end

    test "charts the run outcomes until another widget is selected", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given
      test_case_id = seed_runs_across_time(project)

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}")

      render_async(lv)

      # Then - the card opens on the runs, split by how they came out
      assert [%{"name" => "Successful", "type" => "bar", "stack" => "total"}] =
               chart_option(lv, "test-case-runs-chart")["series"]

      # When
      render_hook(lv, "select_widget", %{"widget" => "flakiness_rate"})

      # Then - no refetch, the series was already loaded
      assert [%{"name" => "Flakiness rate"}] =
               chart_option(lv, "test-case-analytics-chart")["series"]
    end

    test "stacks each bar to the run count of its bucket", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given - one run of every outcome on the same day
      test_case_id = seed_runs_of_every_outcome(project)

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}")

      render_async(lv)

      # Then - every segment is drawn and they add up to the day's runs
      series = chart_option(lv, "test-case-runs-chart")["series"]

      assert Enum.map(series, & &1["name"]) == [
               "Successful",
               "Failed",
               "Flaky",
               "Quarantined",
               "Skipped"
             ]

      totals =
        series
        |> Enum.map(fn segment -> Enum.map(segment["data"], &segment_count/1) end)
        |> Enum.zip_with(&Enum.sum/1)

      assert Enum.max(totals) == 5
    end

    test "rounds the top of each bar rather than every segment in it", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given - a bucket holding every outcome, so the stack is five segments deep
      test_case_id = seed_runs_of_every_outcome(project)

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}")

      render_async(lv)

      # When
      series = chart_option(lv, "test-case-runs-chart")["series"]
      by_name = Map.new(series, &{&1["name"], &1["data"]})
      bucket = Enum.find_index(by_name["Skipped"], &(segment_count(&1) > 0))

      # Then - only the segment that caps the bar is rounded
      assert %{"itemStyle" => %{"borderRadius" => [2, 2, 0, 0]}} = Enum.at(by_name["Skipped"], bucket)
      assert Enum.at(by_name["Successful"], bucket) == 1
      assert Enum.at(by_name["Failed"], bucket) == 1
    end

    test "drops an outcome the test case never had from the bar", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given - runs that all passed
      test_case_id = seed_runs_across_time(project)

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}")

      render_async(lv)

      # Then - a legend entry for an outcome that never happened is noise
      assert Enum.map(chart_option(lv, "test-case-runs-chart")["series"], & &1["name"]) == [
               "Successful"
             ]
    end

    test "charts a rate against a fixed axis so a steady test reads as steady", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given
      test_case_id = seed_runs_across_time(project)

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}?analytics-selected-widget=reliability"
        )

      render_async(lv)

      # Then
      option = chart_option(lv, "test-case-analytics-chart")

      assert [%{"name" => "Test reliability"}] = option["series"]
      assert option["yAxis"]["max"] == 100
    end

    test "leaves a bucket without runs off a rate chart", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given - runs today and three days ago, nothing in between
      test_case_id = seed_runs_across_time(project)

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}?analytics-selected-widget=flakiness_rate"
        )

      render_async(lv)

      # Then - a day with no runs has no flakiness rate, and 0% would claim otherwise
      [flakiness] = chart_option(lv, "test-case-analytics-chart")["series"]
      values = Enum.map(flakiness["data"], &point_value/1)

      assert Enum.any?(values, &is_nil/1)
    end

    test "counts a day without runs as zero rather than as a gap", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given
      test_case_id = seed_runs_across_time(project)

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}")

      render_async(lv)

      # Then - no runs really is a count of zero, unlike a duration or a rate
      [runs] = chart_option(lv, "test-case-runs-chart")["series"]

      refute Enum.any?(runs["data"], &is_nil/1)
      assert 0 in runs["data"]
    end

    test "picking a duration statistic switches the card to the duration chart", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given - the run count is selected, so p90 would otherwise change a number off screen
      test_case_id = seed_runs_across_time(project)

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}")

      render_async(lv)

      # When
      render_hook(lv, "select_duration_type", %{"type" => "p90"})

      # Then
      assert has_element?(lv, "#test-case-duration-chart")
      refute has_element?(lv, "#test-case-runs-chart")
    end

    test "runs the recent history beside the metrics it explains", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given - a test case with something in its history
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case_run.test_case_id,
        event_type: "skipped"
      )

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_run.test_case_id}")

      # Then - a state change and the chart it explains belong on one screen
      assert has_element?(
               lv,
               "[data-part='analytics'] [data-part='analytics-history'] [data-part='timeline-item']"
             )
    end

    test "fills the column beside the chart with history rather than three entries", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given - more history than the column can hold
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      for _event <- 1..12 do
        RunsFixtures.test_case_event_fixture(
          test_case_id: test_case_run.test_case_id,
          event_type: "skipped"
        )
      end

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_run.test_case_id}")

      # Then - the column runs as deep as the analytics beside it, and says so
      # when there is more
      items =
        lv
        |> render()
        |> Floki.parse_document!()
        |> Floki.find("[data-part='analytics-history'] [data-part='timeline-item']")

      assert length(items) == 6
      assert has_element?(lv, "[data-part='analytics-history'] a", "View more")
    end

    test "opens the timeline on the run that introduced the test case", %{
      conn: conn,
      account: account,
      project: project
    } do
      # Given - a test case nobody has quarantined, muted or marked
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      # When
      {:ok, _lv, html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_run.test_case_id}")

      # Then - every test case has a first run, so the column is never an empty frame
      assert html =~ "First run of this test"
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

      {:ok, fetched} = Tests.get_test_case_by_id(test_case_run.test_case_id)
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

      {:ok, fetched} = Tests.get_test_case_by_id(test_case_run.test_case_id)
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

      {:ok, fetched} = Tests.get_test_case_by_id(test_case_run.test_case_id)
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

      Tests.update_test_case(test_case_run.test_case_id, %{is_flaky: true})

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_run.test_case_id}")

      html = lv |> element(~s|button[phx-click="unmark-as-flaky"]|) |> render_click()

      assert html =~ "Mark as flaky"

      {:ok, fetched} = Tests.get_test_case_by_id(test_case_run.test_case_id)
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

      Tests.update_test_case(test_case_run.test_case_id, %{state: "muted"})

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_run.test_case_id}")

      render_hook(lv, "set-state", %{"data" => "enabled"})

      {:ok, fetched} = Tests.get_test_case_by_id(test_case_run.test_case_id)
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
    # `test_fixture/1` seeds one passing and one failing test case, and which
    # comes back first is not fixed. The charts count outcomes, so the tests pin
    # the passing one rather than asserting on whichever arrived.
    test_case_run = passing_test_case_run(project)

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

  defp seed_consecutive_runs(project) do
    test_case_run = passing_test_case_run(project)

    for days_ago <- [1, 2, 3] do
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

  defp seed_runs_of_every_outcome(project) do
    test_case_run = passing_test_case_run(project)

    ran_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.to_naive()

    for {status, is_flaky, is_quarantined} <- [
          {0, false, false},
          {1, false, false},
          {2, false, false},
          {0, true, false},
          {0, false, true}
        ] do
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_run.test_case_id,
        status: status,
        is_flaky: is_flaky,
        is_quarantined: is_quarantined,
        ran_at: ran_at,
        inserted_at: ran_at
      )
    end

    test_case_run.test_case_id
  end

  defp passing_test_case_run(project) do
    {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)
    test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)

    Enum.find(test_run.test_case_runs, &(&1.name == "testExample"))
  end

  # A bar segment is a plain count, or a count carrying the corner radius that
  # caps its bar.
  defp segment_count(%{"value" => count}), do: count
  defp segment_count(count), do: count

  # A line point is `[date, value]` wrapped in the symbol the bucket draws.
  defp point_value(%{"value" => [_date, value]}), do: value

  # Whole-day bounds, so a seeded run cannot land a fraction of a second outside
  # the window it was meant to sit in.
  defp start_of_day_ago(days) do
    Date.utc_today() |> Date.add(-days) |> DateTime.new!(~T[00:00:00], "Etc/UTC") |> DateTime.to_iso8601()
  end

  defp end_of_day_ago(days) do
    Date.utc_today() |> Date.add(-days) |> DateTime.new!(~T[23:59:59], "Etc/UTC") |> DateTime.to_iso8601()
  end

  defp chart_option(lv, chart_id) do
    lv
    |> element("##{chart_id} [data-part='data']")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> JSON.decode!()
  end

  defp widget_trend(lv, widget_id) do
    lv
    |> element("##{widget_id} [data-part='trend']")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp widget_value(lv, widget_id) do
    lv
    |> element("##{widget_id} > [data-part='value']")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> String.trim()
  end

  describe "test case state controls by organization role" do
    setup %{conn: conn} do
      organization = AccountsFixtures.organization_fixture(preload: [:account])
      account = organization.account
      project = ProjectsFixtures.project_fixture(name: "my-project", account_id: account.id)

      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      conn =
        conn
        |> assign(:selected_project, project)
        |> assign(:selected_account, account)

      %{
        conn: conn,
        organization: organization,
        account: account,
        project: project,
        test_case_id: test_case_run.test_case_id
      }
    end

    test "a member that can write sees the state dropdown and the flaky button", %{
      conn: conn,
      organization: organization,
      account: account,
      project: project,
      test_case_id: test_case_id
    } do
      # Given
      member = AccountsFixtures.user_fixture()
      :ok = Accounts.add_user_to_organization(member, organization, role: :user)
      conn = ConnCase.log_in_user(conn, member)

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}")

      # Then
      assert has_element?(lv, "#test-case-state-dropdown")
      assert render(lv) =~ "Mark as flaky"
    end

    test "a viewer sees the state read-only rather than as a control", %{
      conn: conn,
      organization: organization,
      account: account,
      project: project,
      test_case_id: test_case_id
    } do
      # Given
      viewer = AccountsFixtures.user_fixture()
      :ok = Accounts.add_user_to_organization(viewer, organization, role: :viewer)
      conn = ConnCase.log_in_user(conn, viewer)

      {:ok, _} = Tests.update_test_case(test_case_id, %{state: "muted"}, actor_id: account.id)

      # When
      {:ok, lv, html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}")

      # Then — the state stays legible, it just cannot be changed.
      assert html =~ "Muted"
      refute has_element?(lv, "#test-case-state-dropdown")
      refute html =~ "Mark as flaky"
    end

    test "a viewer sees that a test case is flaky", %{
      conn: conn,
      organization: organization,
      account: account,
      project: project,
      test_case_id: test_case_id
    } do
      # Given — a writer reads this off the "Unmark as flaky" button, which a
      # viewer does not get.
      viewer = AccountsFixtures.user_fixture()
      :ok = Accounts.add_user_to_organization(viewer, organization, role: :viewer)
      conn = ConnCase.log_in_user(conn, viewer)

      {:ok, _} = Tests.update_test_case(test_case_id, %{is_flaky: true}, actor_id: account.id)

      # When
      {:ok, _lv, html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}")

      # Then
      assert html =~ "Flaky"
      refute html =~ "Unmark as flaky"
    end

    test "demoting a member to viewer stops an open page from writing", %{
      conn: conn,
      organization: organization,
      account: account,
      project: project,
      test_case_id: test_case_id
    } do
      # Given — a writer with the page already open.
      member = AccountsFixtures.user_fixture()
      :ok = Accounts.add_user_to_organization(member, organization, role: :user)
      conn = ConnCase.log_in_user(conn, member)

      {:ok, lv, _html} =
        live(conn, ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}")

      # When — they are demoted without reloading. The socket outlives the role
      # that opened it, so the permission has to be resolved per write.
      {:ok, _} = Accounts.update_user_role_in_organization(member, organization, :viewer)

      # Then
      Process.flag(:trap_exit, true)
      assert catch_exit(render_hook(lv, "set-state", %{"data" => "muted"}))

      {:ok, test_case} = Tests.get_test_case_by_id(test_case_id)
      assert test_case.state in [nil, "enabled"]
    end

    test "a viewer cannot quarantine a test case by pushing the event directly", %{
      conn: conn,
      organization: organization,
      account: account,
      project: project,
      test_case_id: test_case_id
    } do
      # Given — hiding the control is not the guard; the handler is.
      viewer = AccountsFixtures.user_fixture()
      :ok = Accounts.add_user_to_organization(viewer, organization, role: :viewer)
      conn = ConnCase.log_in_user(conn, viewer)

      path = ~p"/#{account.name}/#{project.name}/tests/test-cases/#{test_case_id}"

      # When / Then — the raise takes the LiveView down, so each event needs its
      # own mount.
      Process.flag(:trap_exit, true)

      for event <- ["set-state", "mark-as-flaky"] do
        {:ok, lv, _html} = live(conn, path)
        assert catch_exit(render_hook(lv, event, %{"data" => "muted"}))
      end

      {:ok, test_case} = Tests.get_test_case_by_id(test_case_id)
      assert test_case.state in [nil, "enabled"]
      refute test_case.is_flaky
    end
  end
end
