defmodule TuistWeb.XcodeOverviewLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.BundlesFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  @render_async_timeout 5_000

  test "bundle size chart follows the default app, URL selection and app changes", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    BundlesFixtures.bundle_fixture(
      project: project,
      name: "ExampleApp",
      install_size: 500_000_000,
      supported_platforms: [:ios],
      inserted_at: DateTime.add(DateTime.utc_now(), -2, :hour)
    )

    BundlesFixtures.bundle_fixture(
      project: project,
      name: "ExampleApp-debug",
      install_size: 2_000_000_000,
      supported_platforms: [:macos],
      inserted_at: DateTime.add(DateTime.utc_now(), -1, :hour)
    )

    path = ~p"/#{organization.account.name}/#{project.name}"
    {:ok, lv, _html} = live(conn, path)
    render_async(lv, @render_async_timeout)

    assert lv |> bundle_chart_values() |> Enum.reject(&(&1 == 0)) |> Enum.uniq() == [500_000_000]

    render_patch(lv, path <> "?bundle-size-app=ExampleApp-debug")
    render_async(lv, @render_async_timeout)

    assert lv |> bundle_chart_values() |> Enum.reject(&(&1 == 0)) |> Enum.uniq() == [2_000_000_000]

    {:ok, selected_lv, _html} = live(conn, path <> "?bundle-size-app=ExampleApp")
    render_async(selected_lv, @render_async_timeout)

    assert selected_lv |> bundle_chart_values() |> Enum.reject(&(&1 == 0)) |> Enum.uniq() == [500_000_000]
  end

  defp bundle_chart_values(lv) do
    lv
    |> element("#average-bundle-size-chart [data-part='data']")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> JSON.decode!()
    |> get_in(["series", Access.at(0), "data"])
    |> Enum.map(fn [_date, value] -> value end)
  end

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
