defmodule TuistWeb.XcodeOverviewLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  @render_async_timeout 5_000

  describe "overview page with test runs" do
    test "renders completed runs when processing test runs exist", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      reject(Tuist.Builds.Analytics, :build_time_analytics, 1)

      {:ok, _test} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          status: "in_progress",
          duration: 0
        )

      {:ok, _test} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          status: "processing",
          duration: 0
        )

      {:ok, _test} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          status: "success",
          duration: 5000
        )

      {:ok, _test} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          status: "failure",
          duration: 3000
        )

      {:ok, live_view, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}")
      render_async(live_view, @render_async_timeout)

      assert has_element?(live_view, "#chart-single-test-run-duration")
      assert has_element?(live_view, "[data-part='test-runs-chart']", "Passed runs")
      assert has_element?(live_view, "[data-part='test-runs-chart']", "Failed runs")
    end
  end

  describe "overview page with code coverage" do
    test "shows the default branch's coverage in the analytics", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      CoverageFixtures.run_with_coverage(
        project,
        organization.account,
        [CoverageFixtures.file("Sources/A.swift", [1, 1, 1, 0], targets: ["App"])],
        %{git_commit_sha: "a", ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60, :second)}
      )

      {:ok, live_view, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}")
      render_async(live_view, @render_async_timeout)

      assert has_element?(live_view, "#widget-code-coverage", "75.0%")
      # The Code Coverage page's chart, with the latest figure, leading to it.
      assert has_element?(live_view, "[data-part='coverage'] #overview-coverage-chart")
      assert has_element?(live_view, "[data-part='coverage'] .tuist-legend", "75.0%")

      assert has_element?(
               live_view,
               "[data-part='coverage'] a[href='/#{organization.account.name}/#{project.name}/tests/coverage']",
               "View more"
             )
    end

    test "picks the coverage chart's period and opens the Code Coverage page on it", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      path = ~p"/#{organization.account.name}/#{project.name}"
      {:ok, live_view, _html} = live(conn, path)

      render_hook(live_view, "coverage_period_changed", %{
        "preset" => "last-12-months",
        "value" => %{"start" => "2026-01-01T00:00:00.000Z", "end" => "2026-01-08T00:00:00.000Z"}
      })

      assert_patch(live_view, path <> "?coverage-date-range=last-12-months")
      render_async(live_view, @render_async_timeout)

      assert has_element?(
               live_view,
               "[data-part='coverage'] a[href='#{path}/tests/coverage?coverage-date-range=last-12-months']",
               "View more"
             )
    end

    test "hides the coverage widget without the coverage flag", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      Mimic.stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)

      {:ok, live_view, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}")
      render_async(live_view, @render_async_timeout)

      refute has_element?(live_view, "#widget-code-coverage")
      refute has_element?(live_view, "[data-part='coverage']")
    end
  end

  describe "overview page with build runs" do
    test "renders without error when processing builds exist", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, _build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          status: "processing",
          duration: 0
        )

      {:ok, _build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          status: "failed_processing",
          duration: 0
        )

      {:ok, _build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          status: "success",
          duration: 5000
        )

      {:ok, _lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}")
    end
  end
end
