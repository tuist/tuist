defmodule TuistWeb.XcodeOverviewLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

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
