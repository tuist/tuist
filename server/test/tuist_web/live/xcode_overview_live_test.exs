defmodule TuistWeb.XcodeOverviewLiveTest do
  use TuistTestSupport.Cases.ConnCase, clickhouse: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "overview page with test runs" do
    test "renders without error when in-progress test runs exist", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, _test} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          status: "in_progress",
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

      {:ok, _lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}")
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
