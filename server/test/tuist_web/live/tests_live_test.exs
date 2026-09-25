defmodule TuistWeb.TestsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @render_async_timeout 1_000

  test "renders a searchable scheme dropdown", %{
    conn: conn,
    project: project
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{project.account.name}/#{project.name}/tests")
    render_async(lv, @render_async_timeout)

    assert has_element?(lv, "#tests-analytics-scheme-dropdown [data-part='search-input']")
  end

  test "renders the shared test dashboard for Bazel projects", %{
    conn: conn,
    organization: organization
  } do
    project = ProjectsFixtures.project_fixture(account: organization.account, build_system: :bazel)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests")
    render_async(lv, @render_async_timeout)

    assert has_element?(lv, "[data-part='analytics']")
    assert has_element?(lv, "#tests-analytics-scheme-dropdown", "Invocation:")
    refute has_element?(lv, "[data-part='selective-testing']")
  end

  describe "code coverage" do
    test "shows the default branch's coverage and, selected, the Code Coverage page's chart", %{
      conn: conn,
      project: project
    } do
      CoverageFixtures.run_with_coverage(
        project,
        project.account,
        [CoverageFixtures.file("Sources/A.swift", [1, 1, 1, 0], targets: ["App"])],
        %{git_commit_sha: "a", ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60, :second)}
      )

      path = ~p"/#{project.account.name}/#{project.name}/tests"
      {:ok, lv, _html} = live(conn, path)
      render_async(lv, @render_async_timeout)

      assert has_element?(lv, "#widget-coverage", "75.0%")
      refute has_element?(lv, "#coverage-chart")

      lv |> element("[phx-click='select_widget'][phx-value-widget='coverage']") |> render_click()
      assert has_element?(lv, "#coverage-chart")
    end

    test "is hidden, and a link selecting it falls back, without the coverage flag", %{
      conn: conn,
      project: project
    } do
      stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)

      {:ok, lv, _html} =
        live(conn, ~p"/#{project.account.name}/#{project.name}/tests?analytics-selected-widget=coverage")

      render_async(lv, @render_async_timeout)

      refute has_element?(lv, "#widget-coverage")
      refute has_element?(lv, "#coverage-chart")
    end
  end
end
