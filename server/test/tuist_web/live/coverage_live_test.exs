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

  defp change_cards(lv, side) do
    lv
    |> element("[data-part='coverage-changes'] [data-part='changes-section'][data-side='#{side}']")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find(".coverage-change-card")
    |> Enum.map(fn card ->
      {card |> Floki.find("[data-part='title']") |> Floki.text(),
       card |> Floki.find("[data-part='subtitle']") |> Floki.text(),
       card |> Floki.find("[data-part='coverage']") |> Floki.text() |> String.trim(),
       card |> Floki.find("[data-part='change']") |> Floki.text() |> String.trim()}
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

    test "opens a chart point's commit, leading back here as shown", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      main_run(project, organization, "a", [file("Sources/A.swift", [1, 0])])
      base = ~p"/#{organization.account.name}/#{project.name}/tests/coverage"
      {:ok, lv, _html} = live(conn, base <> "?coverage-date-range=last-7-days")

      [point] =
        lv
        |> element("#coverage-chart [data-part='data']")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.text()
        |> JSON.decode!()
        |> get_in(["series", Access.at(0), "data"])

      assert point["url"] ==
               "#{base}/commits/a?from=#{URI.encode_www_form(base <> "?coverage-date-range=last-7-days")}"

      assert [_at, 50.0] = point["value"]

      {:ok, commit_lv, _html} = live(conn, point["url"])

      assert has_element?(
               commit_lv,
               "[data-part='back-button'][href='#{base}?coverage-date-range=last-7-days']",
               "Code Coverage"
             )
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
      assert render(element(lv, "#coverage-chart")) =~ "Code Coverage"

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

      assert render(element(lv, "#coverage-chart")) =~ "Code Coverage"
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
      refute has_element?(lv, "[data-part='analytics'] [data-part='view-more']")

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

      from = URI.encode_www_form(path <> "?coverage-date-range=last-7-days")
      assert has_element?(lv, "#coverage-recent-commits-table a[href='#{path}/commits/c6?from=#{from}']")

      view_more =
        lv
        |> element("[data-part='recent-commits'] [data-part='view-more']")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.attribute("a", "href")
        |> List.first()
        |> URI.parse()

      assert view_more.path == path <> "/branches/main"

      assert URI.decode_query(view_more.query) == %{
               "tab" => "commits",
               "coverage-date-range" => "last-7-days",
               "from" => path <> "?coverage-date-range=last-7-days"
             }

      analytics_more =
        lv
        |> element("[data-part='analytics'] [data-part='view-more']")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.attribute("a", "href")
        |> List.first()
        |> URI.parse()

      assert analytics_more.path == path <> "/branches/main"
      assert URI.decode_query(analytics_more.query)["tab"] == "overview"
      assert URI.decode_query(analytics_more.query)["coverage-date-range"] == "last-7-days"
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

      text = &(&1 |> Floki.find(&2) |> Floki.text() |> String.trim())

      rows =
        lv
        |> element("#coverage-recent-commits-table")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("tbody tr")
        |> Enum.map(fn row ->
          {text.(row, "td:nth-child(1)"), text.(row, "[data-part='percentage']"), text.(row, "td:nth-child(3)")}
        end)

      assert rows == [
               {"d", "50.0%", "-25.0%"},
               {"c", "75.0%", "+50.0%"},
               {"a", "25.0%", "—"}
             ]
    end

    test "says when the branch has no commit in the period", %{conn: conn, organization: organization, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")

      assert has_element?(lv, "[data-part='empty-commits']", "No complete commits on main in this period")
      refute has_element?(lv, "[data-part='recent-commits'] [data-part='view-more']")
    end
  end

  describe "recent test runs" do
    test "lists the five newest runs that named the branch in the period, each opening its run", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      runs =
        for index <- 1..6 do
          main_run(project, organization, "c#{index}", [file("Sources/A.swift", [1, 0])], %{
            ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), (index - 8) * 3600, :second),
            scheme: "Scheme#{index}"
          })
        end

      main_run(project, organization, "r", [file("Sources/A.swift", [1, 1])], %{git_branch: "release", scheme: "Release"})

      path = ~p"/#{organization.account.name}/#{project.name}/tests/coverage"
      {:ok, lv, _html} = live(conn, path <> "?coverage-date-range=last-7-days")
      table = lv |> element("#coverage-recent-runs-table") |> render()

      for index <- 2..6, do: assert(table =~ "Scheme#{index}")
      refute table =~ "Scheme1"
      refute table =~ "Release"

      newest = List.last(runs)
      assert has_element?(lv, "#coverage-recent-runs-table a[href$='/tests/test-runs/#{newest.id}']")

      more =
        lv
        |> element("[data-part='recent-runs'] [data-part='view-more']")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.attribute("a", "href")
        |> List.first()
        |> URI.parse()

      assert more.path == path <> "/branches/main"
      assert URI.decode_query(more.query)["tab"] == "runs"
    end

    test "says when no run named the branch in the period", %{conn: conn, organization: organization, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")
      assert has_element?(lv, "[data-part='empty-runs']", "No run gathered coverage on main in this period")
      refute has_element?(lv, "[data-part='recent-runs'] [data-part='view-more']")
    end
  end

  describe "coverage changes" do
    test "lists the files and targets whose coverage moved most over the period", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      in_target = &CoverageFixtures.file(&1, &2, targets: [&3])

      main_run(
        project,
        organization,
        "a",
        [
          in_target.("Sources/A/Up.swift", [1, 0], "Core"),
          in_target.("Sources/Down.swift", [1, 1], "UI"),
          in_target.("Sources/Same.swift", [1, 0], "Net")
        ],
        %{ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -7200, :second)}
      )

      main_run(project, organization, "b", [
        in_target.("Sources/A/Up.swift", [1, 1], "Core"),
        in_target.("Sources/Down.swift", [1, 0], "UI"),
        in_target.("Sources/Same.swift", [1, 0], "Net")
      ])

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")

      assert change_cards(lv, "files") == [
               {"Up.swift", "Sources/A", "100.0%", "+50.0%"},
               {"Down.swift", "Sources", "50.0%", "-50.0%"}
             ]

      assert change_cards(lv, "targets") == [
               {"Core", "1 file", "100.0%", "+50.0%"},
               {"UI", "1 file", "50.0%", "-50.0%"}
             ]

      assert has_element?(lv, "[data-side='files'] .coverage-change-card[data-direction='up']", "Up.swift")
      assert has_element?(lv, "[data-side='files'] .coverage-change-card[data-direction='down']", "Down.swift")
      refute has_element?(lv, "[data-side='targets'] a.coverage-change-card")

      for side <- ~w(files targets) do
        href =
          lv
          |> element("[data-side='#{side}'] [data-part='view-more']")
          |> render()
          |> Floki.parse_fragment!()
          |> Floki.attribute("a", "href")
          |> List.first()

        %URI{path: path, query: query} = URI.parse(href)
        assert path == ~p"/#{organization.account.name}/#{project.name}/tests/coverage/branches/main"

        assert %{"tab" => ^side} = URI.decode_query(query)
      end

      refute has_element?(lv, "[data-part='more-card']")
    end

    test "stacks the changes past the fourth", %{conn: conn, organization: organization, project: project} do
      paths = for index <- 1..5, do: "Sources/F#{index}.swift"

      main_run(project, organization, "a", Enum.map(paths, &file(&1, [0, 0])), %{
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -7200, :second)
      })

      main_run(project, organization, "b", Enum.map(paths, &file(&1, [1, 0])))

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")

      assert length(change_cards(lv, "files")) == 4
      assert has_element?(lv, "[data-side='files'] [data-part='more-card']")
    end

    test "opens a file over the branch and period shown, leading back here", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      main_run(project, organization, "old", [file("Sources/A/Full.swift", [1, 0])], %{
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -7200, :second)
      })

      main_run(project, organization, "new", [file("Sources/A/Full.swift", [1, 1])])
      base = ~p"/#{organization.account.name}/#{project.name}/tests/coverage"
      {:ok, lv, _html} = live(conn, base <> "?coverage-date-range=last-7-days")

      href =
        lv
        |> element("[data-side='files'] a.coverage-change-card")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.attribute("a", "href")
        |> List.first()

      %URI{path: path, query: query} = URI.parse(href)
      assert path == base <> "/files/Sources/A/Full.swift"

      assert URI.decode_query(query) == %{
               "branch" => "main",
               "coverage-date-range" => "last-7-days",
               "from" => base <> "?coverage-date-range=last-7-days"
             }

      {:ok, file_lv, _html} = live(conn, href)

      assert has_element?(
               file_lv,
               "[data-part='back-button'][href='#{base}?coverage-date-range=last-7-days']",
               "Code Coverage"
             )

      # Its header names the file and its directory, not the commit.
      assert has_element?(file_lv, "#coverage-file-page [data-part='label']", "Full.swift")
      badges = file_lv |> element("#coverage-file-page [data-part='badges']") |> render()
      assert badges =~ "Sources/A"
      refute badges =~ "Full.swift"
      refute badges =~ "new"
    end

    test "says when a side has no change", %{conn: conn, organization: organization, project: project} do
      # One file gains what the other loses, so their target holds still.
      main_run(project, organization, "a", [file("Sources/Up.swift", [0, 0]), file("Sources/Down.swift", [1, 0])], %{
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -7200, :second)
      })

      main_run(project, organization, "b", [file("Sources/Up.swift", [1, 0]), file("Sources/Down.swift", [0, 0])])

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")

      assert [{"Down.swift", _, "0.0%", "-50.0%"}, {"Up.swift", _, "50.0%", "+50.0%"}] = change_cards(lv, "files")
      assert has_element?(lv, "[data-side='targets'] [data-part='empty']", "No coverage change")
      assert has_element?(lv, "[data-side='files'] [data-part='view-more']")
      refute has_element?(lv, "[data-side='targets'] [data-part='view-more']")
    end

    test "says when the period has no change to compare", %{conn: conn, organization: organization, project: project} do
      main_run(project, organization, "a", [file("Sources/A.swift", [1, 0])])
      main_run(project, organization, "pending", [file("Sources/A.swift", [1, 1])], %{complete: false})

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")

      assert has_element?(lv, "[data-part='empty-changes']", "No coverage changed on main in this period")
      refute has_element?(lv, ".coverage-change-card")
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
