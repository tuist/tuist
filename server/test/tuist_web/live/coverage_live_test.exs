defmodule TuistWeb.CoverageLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Tests.Test
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistWeb.Errors.NotFoundError

  defp file(path, counts), do: CoverageFixtures.file(path, counts, targets: ["Calculator"])

  defp main_run(project, organization, sha, files, attrs \\ %{}) do
    CoverageFixtures.run_with_coverage(
      project,
      organization.account,
      files,
      Map.merge(%{git_commit_sha: sha, ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600, :second)}, attrs)
    )
  end

  describe "analytics" do
    test "shows the latest chained commit of the branch and its trend, and nothing below but the branches", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      main_run(project, organization, "a", [file("Sources/A.swift", [1, 0, 0, 0])], %{
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -7200, :second)
      })

      main_run(project, organization, "b", [file("Sources/A.swift", [1, 1, 1, 0])])
      main_run(project, organization, "c", [file("Sources/A.swift", [1, 1, 1, 1])], %{partial: true})

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")

      assert has_element?(lv, "#widget-coverage", "75.0%")
      assert has_element?(lv, "#widget-coverage-covered-lines", "3")
      assert has_element?(lv, "#widget-coverage-executable-lines", "4")
      refute has_element?(lv, "#widget-coverage-unmeasured-files")
      assert has_element?(lv, "#coverage-chart")
      refute has_element?(lv, "#coverage-commits-table")
      refute has_element?(lv, "#coverage-gap-files-table")
      refute has_element?(lv, "#coverage-unmeasured-files-table")
    end

    test "gives each widget its own colour, and the chart the selected one's", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      main_run(project, organization, "a", [file("Sources/A.swift", [1, 0])])

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")

      assert has_element?(lv, "#widget-coverage [data-part='legend'][data-color='primary']")
      assert has_element?(lv, "#widget-coverage-covered-lines [data-part='legend'][data-color='secondary']")
      assert has_element?(lv, "#widget-coverage-executable-lines [data-part='legend'][data-color='tertiary']")
      assert render(element(lv, "#coverage-chart")) =~ "noora-chart-primary"

      lv |> element("[phx-value-widget='covered_lines']") |> render_click()
      assert render(element(lv, "#coverage-chart")) =~ "noora-chart-secondary"
    end

    test "leads from the analytics to the default branch's page, on the same period", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      main_run(project, organization, "a", [file("Sources/A.swift", [1, 0])])

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage?coverage-date-range=last-7-days")

      assert has_element?(
               lv,
               "[data-part='view-more'][href='/#{organization.account.name}/#{project.name}/tests/coverage/branches/main?coverage-date-range=last-7-days']"
             )
    end

    test "every widget shows its change over the period and switches the chart to its metric", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      main_run(project, organization, "a", [file("Sources/A.swift", [1, 0, 0, 0])], %{
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -7200, :second)
      })

      main_run(project, organization, "b", [file("Sources/A.swift", [1, 1, 0, 0, 0, 0])])

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")

      assert has_element?(lv, "#widget-coverage-covered-lines [data-part='trend']", "+100.0%")
      assert has_element?(lv, "#widget-coverage-executable-lines [data-part='trend']", "+50.0%")
      assert render(element(lv, "#coverage-chart")) =~ "Code coverage"

      lv |> element("[phx-value-widget='executable_lines']") |> render_click()

      assert render(element(lv, "#coverage-chart")) =~ "Executable lines"
      assert has_element?(lv, "[phx-value-widget='executable_lines'][data-selected]")
      assert_push_event(lv, "replace-url", %{url: "?analytics-selected-widget=executable_lines"})
    end

    test "opens on the widget the address selects, and on coverage for an unknown one", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      main_run(project, organization, "a", [file("Sources/A.swift", [1, 0])])

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/coverage?analytics-selected-widget=covered_lines"
        )

      assert render(element(lv, "#coverage-chart")) =~ "Covered lines"

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage?analytics-selected-widget=bogus")

      assert render(element(lv, "#coverage-chart")) =~ "Code coverage"
    end

    test "reloads once after a burst of runs, whatever branch they ran on", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      main_run(project, organization, "a", [file("Sources/A.swift", [1, 0])])
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")

      send(lv.pid, {:test_created, %Test{git_branch: "feature"}})
      send(lv.pid, {:test_created, %Test{git_branch: "main"}})
      assert :sys.get_state(lv.pid).socket.assigns.reload_scheduled

      main_run(project, organization, "b", [file("Sources/A.swift", [1, 1])])
      send(lv.pid, :reload)

      assert has_element?(lv, "#widget-coverage", "100.0%")
      refute :sys.get_state(lv.pid).socket.assigns.reload_scheduled
    end

    test "reads the page once, when the socket connects", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      main_run(project, organization, "a", [file("Sources/A.swift", [1, 0, 0, 0])])
      path = ~p"/#{organization.account.name}/#{project.name}/tests/coverage"

      html = conn |> get(path) |> html_response(200)
      assert html =~ ~s(data-part="loading")
      refute html =~ ~s(id="widget-coverage")

      {:ok, lv, _html} = live(conn, path)
      assert has_element?(lv, "#widget-coverage")
      refute has_element?(lv, "[data-part='loading']")
    end

    test "a period picked in the date picker lands in the URL", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      main_run(project, organization, "a", [file("Sources/A.swift", [1, 0, 0, 0])])

      path = ~p"/#{organization.account.name}/#{project.name}/tests/coverage"
      {:ok, lv, _html} = live(conn, path)

      render_hook(lv, "coverage_period_changed", %{
        "preset" => "last-7-days",
        "value" => %{"start" => "2026-01-01T00:00:00.000Z", "end" => "2026-01-08T00:00:00.000Z"}
      })

      assert_patch(lv, path <> "?coverage-date-range=last-7-days")
    end

    test "shows the empty state without a measured commit and hides the page without the flag", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")
      assert has_element?(lv, "[data-part='empty-analytics']")

      stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)

      assert_raise NotFoundError, fn ->
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")
      end
    end
  end

  describe "branches" do
    setup %{organization: organization, project: project} do
      main_run(project, organization, "m", [file("Sources/A.swift", [1, 1, 0, 0])])

      main_run(project, organization, "f", [file("Sources/A.swift", [1, 1, 1, 0])], %{
        git_branch: "feature/widgets",
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -1800, :second)
      })

      main_run(project, organization, "p", [file("Sources/A.swift", [1, 1, 1, 1])], %{
        git_branch: "feature/gates",
        is_pull_request: true,
        pull_request_number: 42,
        base_branch: "main",
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -900, :second)
      })

      :ok
    end

    test "lists the branches measured in the period, leading to their pull request or their own page", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")

      table = lv |> element("#coverage-branches-table") |> render()
      assert table =~ "feature/gates"
      assert table =~ "#42"
      assert table =~ "feature/widgets"
      assert table =~ "main"
      assert table =~ "75.0%"

      base = "/#{organization.account.name}/#{project.name}/tests/coverage"
      assert has_element?(lv, "#coverage-branches-table a[href$='#{base}/pull-requests/42']")
      assert has_element?(lv, "#coverage-branches-table a[href$='#{base}/branches/feature%2Fwidgets']")
      assert has_element?(lv, "#coverage-branches-table a[href$='#{base}/branches/main']")
    end

    test "narrows them by search and pages them from a cursor", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      path = ~p"/#{organization.account.name}/#{project.name}/tests/coverage"
      {:ok, lv, _html} = live(conn, path)

      lv |> form("#coverage-branches-filter-form", %{"search" => "widgets"}) |> render_change()
      assert_patch(lv, path <> "?branches-search=widgets")

      table = lv |> element("#coverage-branches-table") |> render()
      assert table =~ "feature/widgets"
      refute table =~ "feature/gates"

      {:ok, lv, _html} = live(conn, path <> "?branches-search=nothing")
      assert has_element?(lv, "[data-part='empty-branches']", "No branch matches nothing")

      for index <- 1..10 do
        main_run(project, organization, "x#{index}", [file("Sources/A.swift", [1, 0])], %{git_branch: "extra/#{index}"})
      end

      {:ok, lv, _html} = live(conn, path)
      assert has_element?(lv, "#ref-feature\\/gates")
      refute has_element?(lv, "#ref-main")
      [_, cursor] = Regex.run(~r/after=([^"&]+)/, render(lv))

      {:ok, lv, _html} = live(conn, path <> "?after=" <> cursor)
      assert has_element?(lv, "#ref-main")
      refute has_element?(lv, "#ref-feature\\/gates")
      assert render(lv) =~ "before="
    end
  end

  describe "coverage gaps" do
    test "the Files tab pages the files without coverage data under their own parameter", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      untested = for index <- 1..25, do: "Sources/Untested#{String.pad_leading("#{index}", 2, "0")}.swift"
      CoverageFixtures.seed_listing(organization.account, "b", ["Sources/A.swift" | untested])
      main_run(project, organization, "b", [file("Sources/A.swift", [1, 1, 0, 0])])

      path = ~p"/#{organization.account.name}/#{project.name}/tests/coverage/commits/b"
      {:ok, lv, _html} = live(conn, path <> "?tab=files")

      first = lv |> element("#coverage-unmeasured-files-table") |> render()
      assert first =~ "Untested01.swift"
      assert first =~ "Untested20.swift"
      refute first =~ "Untested21.swift"

      {:ok, lv, _html} = live(conn, path <> "?tab=files&unmeasured-page=2")

      second = lv |> element("#coverage-unmeasured-files-table") |> render()
      assert second =~ "Untested21.swift"
      assert second =~ "Untested25.swift"
      refute second =~ "Untested20.swift"
    end
  end
end
