defmodule TuistWeb.CoverageLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Test
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistWeb.Errors.NotFoundError

  defp file(path, counts), do: CoverageFixtures.file(path, counts, targets: ["Calculator"])

  # The page draws complete commits only, so a run's commit is signalled
  # complete unless `complete: false` says otherwise.
  defp main_run(project, organization, sha, files, attrs \\ %{}) do
    {complete, attrs} = Map.pop(attrs, :complete, true)

    run =
      CoverageFixtures.run_with_coverage(
        project,
        organization.account,
        files,
        Map.merge(%{git_commit_sha: sha, ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600, :second)}, attrs)
      )

    if complete, do: Commits.signal_complete(project, sha)
    run
  end

  # The dropdown's items render into a portal template, which element/2
  # reaches only as a whole.
  defp branch_items(lv) do
    lv
    |> element("#coverage-branch-dropdown-content-portal")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("[data-part='item']")
    |> Enum.map(&{&1 |> Floki.attribute("data-value") |> List.first(), Floki.attribute(&1, "data-selected") != []})
  end

  defp file_cards(lv, side) do
    lv
    |> element("[data-part='files-coverage-section'][data-side='#{side}']")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find(".coverage-file-card")
    |> Enum.map(fn card ->
      {card |> Floki.find("[data-part='title']") |> Floki.text(),
       card |> Floki.find("[data-part='subtitle']") |> Floki.text(),
       card |> Floki.find("[data-part='coverage']") |> Floki.text() |> String.trim()}
    end)
  end

  describe "analytics" do
    test "shows the latest chained commit of the branch and its trend, and nothing below", %{
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

      assert has_element?(lv, "[data-part='analytics']", "Analytics")
      refute render(lv) =~ "Default Branch Analytics"
      assert has_element?(lv, "#widget-coverage", "75.0%")
      assert has_element?(lv, "#widget-coverage-covered-lines", "3")
      assert has_element?(lv, "#widget-coverage-executable-lines", "4")
      refute has_element?(lv, "#widget-coverage-unmeasured-files")
      assert has_element?(lv, "#coverage-chart")
      # Few enough commits to draw each one: the tooltip titles them by date and time.
      assert render(element(lv, "#coverage-chart")) =~ "&quot;dateFormat&quot;:&quot;minute&quot;"
      refute has_element?(lv, "#coverage-commits-table")
      refute has_element?(lv, "#coverage-branches-table")
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

  describe "recent commits" do
    test "lists the branch's five most recent complete commits in the period, each leading to its page", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      for index <- 1..7 do
        main_run(project, organization, "c#{index}", [file("Sources/A.swift", [1, 0])], %{
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), (index - 8) * 3600, :second),
          complete: index != 7
        })
      end

      path = ~p"/#{organization.account.name}/#{project.name}/tests/coverage"
      {:ok, lv, _html} = live(conn, path <> "?coverage-date-range=last-7-days")

      table = lv |> element("#coverage-recent-commits-table") |> render()

      # c7 is pending, so the five are c2 to c6.
      for index <- 2..6, do: assert(table =~ "c#{index}")
      refute table =~ "c1"
      refute table =~ "c7"

      refute has_element?(lv, "#coverage-recent-commits-table a")

      assert has_element?(
               lv,
               "[data-part='recent-commits'] [data-part='view-more'][href='#{path}/commits?coverage-date-range=last-7-days']"
             )

      refute has_element?(lv, "[data-part='analytics'] [data-part='view-more']")
    end

    test "shows how far each commit moved coverage from the complete commit before it", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # a 25%, b 50% (pending), c 75%, d 50%: c is read against a, skipping b.
      for {sha, counts, hours, complete} <- [
            {"a", [1, 0, 0, 0], 4, true},
            {"b", [1, 1, 0, 0], 3, false},
            {"c", [1, 1, 1, 0], 2, true},
            {"d", [1, 1, 0, 0], 1, true}
          ] do
        main_run(project, organization, sha, [file("Sources/A.swift", counts)], %{
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -hours * 3600, :second),
          complete: complete
        })
      end

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")

      rows =
        lv
        |> element("#coverage-recent-commits-table")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("tbody tr")
        |> Enum.map(fn row -> row |> Floki.find("td") |> Enum.map(&String.trim(Floki.text(&1))) end)

      assert Enum.map(rows, &{Enum.at(&1, 0), Enum.at(&1, 2)}) == [{"d", "-25.0%"}, {"c", "+50.0%"}, {"a", "—"}]
    end

    test "says when the branch has no commit in the period", %{conn: conn, organization: organization, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")

      assert has_element?(lv, "[data-part='empty-commits']", "No complete commits on main in this period")
    end
  end

  describe "files coverage" do
    test "shows the latest complete commit's most and least covered files, up to four of each", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # An older complete commit and a newer pending one are not read.
      main_run(project, organization, "old", [file("Sources/Old.swift", [1, 1])], %{
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -7200, :second)
      })

      main_run(project, organization, "new", [
        file("Sources/A/Full.swift", [1, 1]),
        file("Sources/A/Big.swift", [1, 1, 1, 0]),
        file("Sources/B/Half.swift", [1, 0]),
        file("Sources/B/None.swift", [0, 0, 0]),
        file("Sources/B/Small.swift", [0]),
        file("Sources/C/Most.swift", [1, 1, 1, 1, 0])
      ])

      main_run(project, organization, "pending", [file("Sources/Pending.swift", [0])], %{
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60, :second),
        complete: false
      })

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")

      assert file_cards(lv, "highest") == [
               {"Full.swift", "Sources/A", "100.0%"},
               {"Most.swift", "Sources/C", "80.0%"},
               {"Big.swift", "Sources/A", "75.0%"},
               {"Half.swift", "Sources/B", "50.0%"}
             ]

      # Uncovered alike, the bigger file first.
      assert file_cards(lv, "lowest") == [
               {"None.swift", "Sources/B", "0.0%"},
               {"Small.swift", "Sources/B", "0.0%"},
               {"Half.swift", "Sources/B", "50.0%"},
               {"Big.swift", "Sources/A", "75.0%"}
             ]

      assert has_element?(lv, "[data-side='highest'] [data-part='more-card']")
    end

    test "says when no commit of the branch is complete in the period", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      main_run(project, organization, "pending", [file("Sources/A.swift", [1, 0])], %{complete: false})

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")

      assert has_element?(lv, "[data-part='empty-files']", "No complete commit on main in this period")
      refute has_element?(lv, ".coverage-file-card")
    end
  end

  describe "branch selection" do
    setup %{organization: organization, project: project} do
      main_run(project, organization, "m", [file("Sources/A.swift", [1, 0, 0, 0])])
      main_run(project, organization, "r", [file("Sources/A.swift", [1, 1, 1, 0])], %{git_branch: "release"})

      main_run(project, organization, "p", [file("Sources/A.swift", [1, 1, 1, 1])], %{
        git_branch: "feature/gates",
        is_pull_request: true,
        pull_request_number: 42,
        base_branch: "main"
      })

      :ok
    end

    test "lists the branches without a pull request, the default branch selected", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")

      assert has_element?(lv, "#coverage-branch-dropdown [data-part='search-input']")
      assert branch_items(lv) == [{"main", true}, {"release", false}]
      assert has_element?(lv, "#widget-coverage", "25.0%")
    end

    test "shows the selected branch's analytics and recent commits", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      path = ~p"/#{organization.account.name}/#{project.name}/tests/coverage"
      {:ok, lv, _html} = live(conn, path)

      assert lv |> element("#coverage-branch-dropdown-content-portal") |> render() =~
               ~s(href="?branch=release")

      render_patch(lv, path <> "?branch=release")

      assert branch_items(lv) == [{"main", false}, {"release", true}]
      assert has_element?(lv, "#widget-coverage", "75.0%")
      assert lv |> element("#coverage-recent-commits-table") |> render() =~ ">r<"
      refute lv |> element("#coverage-recent-commits-table") |> render() =~ ">m<"
    end
  end

  describe "coverage gaps" do
    test "a commit's pages do not list the files without coverage data", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      CoverageFixtures.seed_listing(organization.account, "b", ["Sources/A.swift", "Sources/Untested.swift"])
      main_run(project, organization, "b", [file("Sources/A.swift", [1, 1, 0, 0])])

      path = ~p"/#{organization.account.name}/#{project.name}/tests/coverage/commits/b"

      {:ok, lv, _html} = live(conn, path)
      refute render(lv) =~ "Untested.swift"

      {:ok, lv, _html} = live(conn, path <> "?tab=files")
      assert has_element?(lv, "#coverage-files-table", "A.swift")
      refute render(lv) =~ "Untested.swift"
    end
  end
end
