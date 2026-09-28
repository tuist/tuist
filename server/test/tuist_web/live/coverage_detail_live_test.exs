defmodule TuistWeb.CoverageDetailLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.History
  alias Tuist.Tests.Test
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistWeb.Errors.NotFoundError

  defp file(path, counts), do: CoverageFixtures.file(path, counts, targets: ["Calculator"])

  setup %{organization: organization, project: project} do
    CoverageFixtures.seed_history(organization.account, [
      CoverageFixtures.commit("a", [], 0),
      CoverageFixtures.commit("b", ["a"], 1)
    ])

    run =
      CoverageFixtures.run_with_coverage(
        project,
        organization.account,
        [file("Sources/A.swift", [1, 1, 0, 0]), file("Sources/B.swift", [1, 1])],
        %{git_commit_sha: "b"}
      )

    %{base: ~p"/#{organization.account.name}/#{project.name}/tests/coverage", run: run}
  end

  test "reads the commit on the connected render only", %{conn: conn, base: base} do
    html = conn |> get(base <> "/commits/b") |> html_response(200)
    assert html =~ ~s(data-part="loading")

    {:ok, lv, _html} = live(conn, base <> "/commits/b")
    refute has_element?(lv, "[data-part='loading']")
  end

  test "shows a commit's totals, complete once signalled", %{conn: conn, base: base, project: project} do
    {:ok, lv, _html} = live(conn, base <> "/commits/b")

    assert has_element?(lv, "h1[aria-label='Commit b']", "b")
    assert has_element?(lv, "#copy-commit-sha-button[data-clipboard-value='b']")
    assert has_element?(lv, "[data-part='kind'][data-kind='commit']")
    refute has_element?(lv, "#coverage-detail [data-part='badges'] .noora-badge", "b")

    assert has_element?(lv, "#widget-coverage", "66.7%")
    assert has_element?(lv, "#widget-covered-lines", "4")
    assert has_element?(lv, "#widget-executable-lines", "6")
    refute has_element?(lv, ".noora-alert")
    assert lv |> element("#coverage-detail [data-part='status']") |> render() =~ "Pending"
    refute has_element?(lv, "[data-part='files-coverage']")
    refute has_element?(lv, "[data-part='sources-card']")

    Commits.signal_complete(project, "b")

    {:ok, lv, _html} = live(conn, base <> "/commits/b")
    assert lv |> element("#coverage-detail [data-part='status']") |> render() =~ "Complete"
  end

  test "states a partial run as a badge beside the status, not as a banner", %{
    conn: conn,
    base: base,
    organization: organization,
    project: project
  } do
    CoverageFixtures.run_with_coverage(project, organization.account, [file("Sources/A.swift", [1, 0])], %{
      git_commit_sha: "a",
      partial: true
    })

    {:ok, lv, _html} = live(conn, base <> "/commits/a")

    assert has_element?(lv, "#coverage-detail [data-part='badges'] [data-part='partial']", "Partial run")
    refute has_element?(lv, ".noora-alert")

    {:ok, lv, _html} = live(conn, base <> "/commits/b")
    refute has_element?(lv, "#coverage-detail [data-part='partial']")
  end

  test "reloads for the commit's own runs only, and keeps the page when its coverage is gone", %{
    conn: conn,
    base: base,
    project: project
  } do
    {:ok, lv, _html} = live(conn, base <> "/commits/b")

    send(lv.pid, {:test_created, %Test{git_commit_sha: "a"}})
    refute :sys.get_state(lv.pid).socket.assigns.reload_scheduled

    send(lv.pid, {:test_created, %Test{git_commit_sha: "b"}})
    assert :sys.get_state(lv.pid).socket.assigns.reload_scheduled

    Tuist.Repo.delete_all(from(c in Tuist.Tests.CoverageCommit, where: c.project_id == ^project.id))
    send(lv.pid, :reload)

    assert has_element?(lv, "#widget-coverage", "66.7%")
  end

  test "lists the commit's targets, files and runs in their own tabs", %{conn: conn, base: base, run: run} do
    {:ok, lv, _html} = live(conn, base <> "/commits/b?tab=targets")
    assert has_element?(lv, "#coverage-targets-table", "Calculator")

    {:ok, lv, _html} = live(conn, base <> "/commits/b?tab=files")
    assert has_element?(lv, "#coverage-files-table", "A.swift")
    assert has_element?(lv, "#coverage-files-table", "B.swift")

    {:ok, lv, _html} = live(conn, base <> "/commits/b?tab=runs")
    assert has_element?(lv, "#coverage-runs-table a[href$='/tests/test-runs/#{run.id}']")
    # One page still shows its buttons, disabled, as every list paged by cursor does.
    assert has_element?(lv, "[data-part='runs-table'] .tuist-pagination button[disabled]", "Next")
  end

  test "searches, filters, sorts and pages the commit's targets, least covered first by default", %{
    conn: conn,
    base: base,
    organization: organization,
    project: project
  } do
    files =
      [
        CoverageFixtures.file("Sources/Calculator.swift", [1, 0], targets: ["Calculator"]),
        CoverageFixtures.file("Sources/Networking.swift", [1, 1], targets: ["Networking"]),
        CoverageFixtures.file("Sources/Storage.swift", [0, 0], targets: ["Storage"])
      ] ++
        for index <- 1..20 do
          CoverageFixtures.file("Sources/Feature#{index}.swift", [1, 1, 1], targets: ["Feature#{index}"])
        end

    CoverageFixtures.run_with_coverage(project, organization.account, files, %{git_commit_sha: "a"})
    order = fn lv, names -> Enum.sort_by(names, &(lv |> render() |> :binary.match(&1) |> elem(0))) end

    {:ok, lv, _html} = live(conn, base <> "/commits/a?tab=targets")
    assert order.(lv, ["Feature1", "Calculator", "Storage"]) == ["Storage", "Calculator", "Feature1"]
    assert has_element?(lv, "#coverage-targets-sort-by-label-portal", "Coverage")
    assert has_element?(lv, "#coverage-targets-table", "Feature1")
    refute has_element?(lv, "#coverage-targets-table", "Networking")

    {:ok, lv, _html} = live(conn, base <> "/commits/a?tab=targets&page=2")
    assert has_element?(lv, "#coverage-targets-table", "Networking")

    lv |> form("#coverage-targets-search-form", %{search: "net"}) |> render_change()
    assert_patch(lv, base <> "/commits/a?tab=targets&targets-search=net")
    assert has_element?(lv, "#coverage-targets-table", "Networking")
    refute has_element?(lv, "#coverage-targets-table", "Calculator")

    not_features = "filter_target_name_op=!%3D~&filter_target_name_val=feature"
    {:ok, lv, _html} = live(conn, base <> "/commits/a?tab=targets&#{not_features}")
    assert has_element?(lv, "#target_name", "Target name")
    refute has_element?(lv, "#coverage-targets-table", "Feature1")

    {:ok, lv, _html} =
      live(conn, base <> "/commits/a?tab=targets&targets-sort-by=name&targets-sort-order=desc&#{not_features}")

    assert order.(lv, ["Calculator", "Storage", "Networking"]) == ["Storage", "Networking", "Calculator"]

    {:ok, lv, _html} = live(conn, base <> "/commits/a?tab=targets&targets-search=missing")
    assert has_element?(lv, "#coverage-targets-table", "No target matches these filters")
  end

  test "searches and sorts the commit's files, least covered first by default", %{conn: conn, base: base} do
    order = fn lv, names -> Enum.sort_by(names, &(lv |> render() |> :binary.match(&1) |> elem(0))) end

    {:ok, lv, _html} = live(conn, base <> "/commits/b?tab=files")
    assert order.(lv, ["B.swift", "A.swift"]) == ["A.swift", "B.swift"]
    assert has_element?(lv, "#coverage-files-sort-by-label-portal", "File coverage")

    {:ok, lv, _html} = live(conn, base <> "/commits/b?tab=files&files-sort-by=coverage&files-sort-order=desc")
    assert order.(lv, ["A.swift", "B.swift"]) == ["B.swift", "A.swift"]

    lv |> form("#coverage-files-search-form", %{search: "b.swift"}) |> render_change()
    assert_patch(lv, base <> "/commits/b?files-search=b.swift&files-sort-by=coverage&files-sort-order=desc&tab=files")
    assert has_element?(lv, "#coverage-files-table", "B.swift")
    refute has_element?(lv, "#coverage-files-table", "A.swift")

    {:ok, lv, _html} = live(conn, base <> "/commits/b?tab=files&files-search=missing")
    assert has_element?(lv, "#coverage-files-table", "No file matches this search")
    refute has_element?(lv, "[data-part='empty-files']")
  end

  test "searches, filters and pages the commit's runs by cursor, most recent first", %{
    conn: conn,
    base: base,
    organization: organization,
    project: project,
    run: run
  } do
    now = NaiveDateTime.utc_now()

    widgets =
      CoverageFixtures.run_with_coverage(project, organization.account, [file("Sources/W.swift", [1, 1])], %{
        git_commit_sha: "b",
        scheme: "Widgets",
        partial: true,
        ran_at: NaiveDateTime.add(now, -3600)
      })

    kits =
      for index <- 1..20 do
        CoverageFixtures.run_with_coverage(project, organization.account, [file("Sources/K#{index}.swift", [0, 1])], %{
          git_commit_sha: "b",
          scheme: "Kit#{index}",
          ran_at: NaiveDateTime.add(now, -7200 - index)
        })
      end

    href = fn run -> "#coverage-runs-table a[href$='/tests/test-runs/#{run.id}']" end

    {:ok, lv, _html} = live(conn, base <> "/commits/b?tab=runs")
    rows = lv |> element("#coverage-runs-table") |> render()
    assert :binary.match(rows, "Widgets") < :binary.match(rows, "Kit1<")
    refute has_element?(lv, "#coverage-runs-sort-by")
    assert has_element?(lv, href.(widgets))
    refute has_element?(lv, href.(List.last(kits)))
    refute has_element?(lv, "#coverage-runs-table", "Kit20")

    lv |> element("[data-part='runs-table'] a", "Next") |> render_click()
    assert has_element?(lv, href.(List.last(kits)))
    refute has_element?(lv, href.(widgets))

    lv |> element("[data-part='runs-table'] a", "Prev") |> render_click()
    assert has_element?(lv, href.(widgets))

    lv |> form("#coverage-runs-search-form", %{search: "widg"}) |> render_change()
    assert has_element?(lv, href.(widgets))
    refute has_element?(lv, href.(run))

    {:ok, lv, _html} = live(conn, base <> "/commits/b?tab=runs&filter_run_kind_op=%3D%3D&filter_run_kind_val=partial")
    assert has_element?(lv, "#run_kind", "Run")
    assert has_element?(lv, href.(widgets))
    refute has_element?(lv, href.(run))

    {:ok, lv, _html} = live(conn, base <> "/commits/b?tab=runs&filter_run_kind_op=!%3D&filter_run_kind_val=partial")
    assert has_element?(lv, href.(run))
    refute has_element?(lv, href.(widgets))

    {:ok, lv, _html} = live(conn, base <> "/commits/b?tab=runs&filter_run_scheme_op=%3D%3D&filter_run_scheme_val=App")
    assert has_element?(lv, href.(run))
    refute has_element?(lv, href.(widgets))

    {:ok, lv, _html} = live(conn, base <> "/commits/b?tab=runs&runs-search=missing")
    assert has_element?(lv, "#coverage-runs-table", "No run matches these filters")
  end

  test "opens a file of the commit on its own page, with its uncovered lines", %{conn: conn, base: base} do
    {:ok, lv, _html} = live(conn, base <> "/commits/b?tab=files")
    from = URI.encode_www_form("#{base}/commits/b?tab=files")

    assert has_element?(
             lv,
             "#coverage-files-table a[href='#{base}/files/Sources/A.swift?commit=b&tab=files&from=#{from}']"
           )

    {:ok, lv, _html} = live(conn, base <> "/files/Sources/A.swift?commit=b&tab=overview")
    assert has_element?(lv, "[data-part='back-button'][href='#{base}/commits/b?tab=overview']")
    assert has_element?(lv, "[data-part='kind'][data-kind='file']")
    assert has_element?(lv, "[data-part='title'] h1[data-part='label']", "A.swift")
    assert has_element?(lv, "[data-part='file-summary-card']", "Analytics")
    assert has_element?(lv, "#widget-coverage-file-percentage", "50.0%")
    refute has_element?(lv, "#coverage-chart")
    refute has_element?(lv, "#coverage-file-targets")
    refute has_element?(lv, "#coverage-file-uncovered-lines")
    refute has_element?(lv, "[data-part='file-details']")

    {:ok, lv, _html} = live(conn, base <> "/files/Sources/Missing.swift?commit=b")
    assert has_element?(lv, "[data-part='file-empty']")
  end

  test "searches, sorts and pages a file's functions, least covered first by default", %{
    conn: conn,
    base: base,
    organization: organization,
    project: project
  } do
    # 21 one-line functions: `helper1`..`helper20` ran, `zeta` did not.
    counts = List.duplicate(1, 20) ++ [0]

    functions =
      for {count, line} <- Enum.with_index(counts, 1) do
        name = if line == 21, do: "zeta()", else: "helper#{line}()"
        %{name: name, line_number: line, execution_count: count, covered_lines: count, executable_lines: 1}
      end

    file = "Sources/F.swift" |> CoverageFixtures.file(counts) |> Map.put(:functions, functions)
    CoverageFixtures.run_with_coverage(project, organization.account, [file], %{git_commit_sha: "a"})
    {:ok, lv, _html} = live(conn, base <> "/files/Sources/F.swift?commit=a")
    rows = lv |> element("#coverage-functions-table tbody") |> render()
    assert :binary.match(rows, "zeta()") < :binary.match(rows, "helper1()")
    assert has_element?(lv, "#coverage-functions-sort-by-label-portal", "Coverage")
    refute has_element?(lv, "#coverage-functions-table", "helper20()")

    {:ok, lv, _html} = live(conn, base <> "/files/Sources/F.swift?commit=a&page=2")
    assert has_element?(lv, "#coverage-functions-table", "helper20()")

    {:ok, lv, _html} =
      live(conn, base <> "/files/Sources/F.swift?commit=a&functions-sort-by=name&functions-sort-order=desc")

    rows = lv |> element("#coverage-functions-table tbody") |> render()
    assert :binary.match(rows, "zeta()") < :binary.match(rows, "helper9()")

    # Most executed first: the one function that never ran is the 21st, on the second page.
    {:ok, lv, _html} = live(conn, base <> "/files/Sources/F.swift?commit=a&functions-sort-by=executions")
    assert has_element?(lv, "#coverage-functions-sort-by-label-portal", "Executions")
    refute has_element?(lv, "#coverage-functions-table", "zeta()")

    {:ok, lv, _html} =
      live(conn, base <> "/files/Sources/F.swift?commit=a&functions-sort-by=line&functions-sort-order=desc")

    rows = lv |> element("#coverage-functions-table tbody") |> render()
    assert :binary.match(rows, "zeta()") < :binary.match(rows, "helper20()")

    {:ok, lv, _html} =
      live(conn, base <> "/files/Sources/F.swift?commit=a&functions-sort-by=covered_lines&functions-sort-order=asc")

    rows = lv |> element("#coverage-functions-table tbody") |> render()
    assert :binary.match(rows, "zeta()") < :binary.match(rows, "helper1()")

    lv |> form("#coverage-functions-search-form", %{search: "ZETA"}) |> render_change()
    assert has_element?(lv, "#coverage-functions-table", "zeta()")
    refute has_element?(lv, "#coverage-functions-table", "helper1()")

    {:ok, lv, _html} = live(conn, base <> "/files/Sources/F.swift?commit=a&functions-search=missing")
    assert has_element?(lv, "#coverage-functions-table", "No function matches this search")
  end

  test "is not found for a commit without coverage", %{conn: conn, base: base} do
    assert_raise NotFoundError, fn -> live(conn, base <> "/commits/nothing") end
    assert_raise NotFoundError, fn -> live(conn, base <> "/files/Sources/A.swift?commit=nothing") end
  end

  describe "a branch" do
    test "reads as its head commit, with its trend over the period, its commits and its runs", %{
      conn: conn,
      base: base,
      run: run
    } do
      {:ok, lv, _html} = live(conn, base <> "/branches/main")

      assert has_element?(lv, "h1[aria-label='Branch main']", "main")
      assert has_element?(lv, "[data-part='kind'][data-kind='branch']")
      assert has_element?(lv, "#widget-coverage", "66.7%")
      assert has_element?(lv, "#coverage-chart")
      assert has_element?(lv, "[data-part='analytics'] #coverage-analytics-date-range-picker")
      refute has_element?(lv, "[data-part='analytics']", "Default Branch Analytics: main")
      assert render(lv) =~ "?tab=commits"

      refute has_element?(lv, "[data-part='sources-card']")

      {:ok, lv, _html} = live(conn, base <> "/branches/main?tab=commits")
      assert has_element?(lv, "[data-part='commits-table'] .tuist-pagination button[disabled]", "Prev")
      from = URI.encode_www_form("#{base}/branches/main?tab=commits")
      assert has_element?(lv, "#coverage-commits-table a[href$='/tests/coverage/commits/b?from=#{from}']")

      # The commit, and a file of it, lead back to the branch as it was.
      {:ok, lv, _html} = live(conn, base <> "/commits/b?from=#{from}")
      assert has_element?(lv, "[data-part='back-button'][href='#{base}/branches/main?tab=commits']", "Branch main")

      {:ok, lv, _html} = live(conn, base <> "/files/Sources/A.swift?commit=b&from=#{from}")
      assert has_element?(lv, "[data-part='back-button'][href='#{base}/branches/main?tab=commits']", "Branch main")

      # Anywhere else is not somewhere to lead back to.
      {:ok, lv, _html} = live(conn, base <> "/commits/b?from=" <> URI.encode_www_form("https://example.com/x"))
      assert has_element?(lv, "[data-part='back-button'][href='#{base}']", "Code coverage")

      {:ok, lv, _html} = live(conn, base <> "/branches/main?tab=runs")
      assert has_element?(lv, "#coverage-runs-table a[href$='/tests/test-runs/#{run.id}']")
    end

    test "opens its files with their coverage over the branch's period", %{
      conn: conn,
      base: base,
      organization: organization,
      project: project
    } do
      CoverageFixtures.run_with_coverage(project, organization.account, [file("Sources/A.swift", [1, 0, 0, 0])], %{
        git_commit_sha: "a",
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600)
      })

      assert Enum.map(History.file_points(project, "main", "Sources/A.swift"), &{&1.git_commit_sha, &1.coverage}) ==
               [{"a", 25.0}, {"b", 50.0}]

      {:ok, lv, _html} = live(conn, base <> "/branches/main?tab=files")
      assert has_element?(lv, "#coverage-files-table a[href*='/files/Sources/A.swift?commit=b&branch=main&tab=files']")

      {:ok, lv, _html} = live(conn, base <> "/files/Sources/A.swift?commit=b&branch=main")
      assert has_element?(lv, "[data-part='analytics'] #coverage-file-date-range-picker")
      assert has_element?(lv, "#coverage-chart")
      assert has_element?(lv, "#widget-coverage", "50.0%")
      refute has_element?(lv, "[data-part='file-summary-card']")

      {:ok, lv, _html} = live(conn, base <> "/files/Sources/Missing.swift?commit=b&branch=main")
      assert has_element?(lv, "[data-part='file-empty']")
    end

    test "is found by a name with slashes, encoded or not", %{
      conn: conn,
      base: base,
      organization: organization,
      project: project
    } do
      CoverageFixtures.run_with_coverage(project, organization.account, [file("Sources/A.swift", [1, 0])], %{
        git_commit_sha: "f",
        git_branch: "feature/widgets"
      })

      {:ok, lv, _html} = live(conn, base <> "/branches/feature/widgets")
      assert has_element?(lv, "h1[aria-label='Branch feature/widgets']", "feature/widgets")

      {:ok, lv, _html} = live(conn, base <> "/branches/feature%2Fwidgets")
      assert has_element?(lv, "h1[aria-label='Branch feature/widgets']", "feature/widgets")
    end
  end

  describe "a pull request" do
    setup %{organization: organization, project: project} do
      pull_request = %{git_branch: "feature/gates", is_pull_request: true, pull_request_number: 7, base_branch: "main"}

      older =
        CoverageFixtures.run_with_coverage(
          project,
          organization.account,
          [file("Sources/A.swift", [1, 0, 0, 0])],
          Map.merge(pull_request, %{
            git_commit_sha: "p1",
            ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -7200, :second)
          })
        )

      newer =
        CoverageFixtures.run_with_coverage(
          project,
          organization.account,
          [file("Sources/A.swift", [1, 1, 1, 0])],
          Map.merge(pull_request, %{
            git_commit_sha: "p2",
            ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600, :second)
          })
        )

      %{older: older, newer: newer}
    end

    test "reads as its newest commit, from its branch into its base, with every commit and run", %{
      conn: conn,
      base: base,
      older: older,
      newer: newer
    } do
      {:ok, lv, _html} = live(conn, base <> "/pull-requests/7")

      assert has_element?(lv, "h1[aria-label='Pull request #7']", "#7")
      assert has_element?(lv, "[data-part='kind'][data-kind='pull_request']")
      assert has_element?(lv, "[data-part='branches']", "feature/gates")
      assert has_element?(lv, "[data-part='branches']", "main")
      assert has_element?(lv, "#widget-coverage", "75.0%")
      refute has_element?(lv, "#coverage-commit-dropdown")

      {:ok, lv, _html} = live(conn, base <> "/pull-requests/7?tab=commits")
      table = lv |> element("#coverage-commits-table") |> render()
      assert table =~ "p2"
      assert table =~ "p1"
      assert table =~ "Pending"
      refute table =~ "Not chained"

      {:ok, lv, _html} = live(conn, base <> "/pull-requests/7?tab=runs")
      assert has_element?(lv, "#coverage-runs-table a[href$='/tests/test-runs/#{older.id}']")
      assert has_element?(lv, "#coverage-runs-table a[href$='/tests/test-runs/#{newer.id}']")
    end

    test "lists the commits and runs of the period, picked in those cards' headers", %{conn: conn, base: base} do
      {:ok, lv, _html} = live(conn, base <> "/pull-requests/7?tab=commits")
      assert has_element?(lv, "[data-part='commits'] #coverage-commits-date-range-picker")

      {:ok, lv, _html} = live(conn, base <> "/pull-requests/7?tab=runs")
      assert has_element?(lv, "[data-part='runs-card'] #coverage-runs-date-range-picker")

      week_ago = DateTime.utc_now() |> DateTime.add(-7, :day) |> DateTime.to_iso8601()
      yesterday = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.to_iso8601()

      period =
        URI.encode_query(%{
          "coverage-date-range" => "custom",
          "coverage-start-date" => week_ago,
          "coverage-end-date" => yesterday
        })

      {:ok, lv, _html} = live(conn, base <> "/pull-requests/7?tab=commits&" <> period)
      assert has_element?(lv, "[data-part='empty-commits']")

      {:ok, lv, _html} = live(conn, base <> "/pull-requests/7?tab=runs&" <> period)
      assert has_element?(lv, "[data-part='empty-runs']")
    end

    test "searches its commits by SHA and filters them by status", %{conn: conn, base: base, project: project} do
      Commits.signal_complete(project, "p1")

      {:ok, lv, _html} = live(conn, base <> "/pull-requests/7?tab=commits")
      refute has_element?(lv, "#coverage-commits-table th", "Scheme")

      lv |> form("#coverage-commits-filter-form", %{"search" => "P1"}) |> render_change()
      assert_patch(lv, base <> "/pull-requests/7?commits-search=P1&tab=commits")
      table = lv |> element("#coverage-commits-table") |> render()
      assert table =~ "p1"
      refute table =~ "p2"

      {:ok, lv, _html} = live(conn, base <> "/pull-requests/7?tab=commits&commits-status=pending")
      table = lv |> element("#coverage-commits-table") |> render()
      assert table =~ "p2"
      refute table =~ "p1"
      assert has_element?(lv, "#coverage-commits-status-dropdown-label-portal", "Pending")

      {:ok, lv, _html} = live(conn, base <> "/pull-requests/7?tab=commits&commits-search=p1&commits-status=pending")
      assert has_element?(lv, "[data-part='empty-commits']", "No commit matches these filters")
      assert has_element?(lv, "#coverage-commits-filter-form")
    end

    test "opens its files as its newest commit's, without a trend", %{conn: conn, base: base} do
      {:ok, lv, _html} = live(conn, base <> "/pull-requests/7?tab=files")

      assert has_element?(
               lv,
               "#coverage-files-table a[href*='/files/Sources/A.swift?commit=p2&pull-request=7&tab=files']"
             )

      {:ok, lv, _html} = live(conn, base <> "/files/Sources/A.swift?commit=p2&pull-request=7")
      assert has_element?(lv, "[data-part='file-summary-card']", "Analytics")
      refute has_element?(lv, "#coverage-chart")
    end

    test "reads as its newest commit whatever commit the address names", %{conn: conn, base: base} do
      {:ok, lv, _html} = live(conn, base <> "/pull-requests/7?commit=p1")
      assert has_element?(lv, "#widget-coverage", "75.0%")
    end
  end

  test "a commit has no commits tab of its own", %{conn: conn, base: base} do
    {:ok, lv, _html} = live(conn, base <> "/commits/b")
    refute render(lv) =~ "tab=commits"

    {:ok, lv, _html} = live(conn, base <> "/commits/b?tab=commits")
    assert has_element?(lv, "[data-part='summary-card']")
  end

  test "is not found for a branch or a pull request without coverage", %{conn: conn, base: base} do
    assert_raise NotFoundError, fn -> live(conn, base <> "/branches/nothing") end
    assert_raise NotFoundError, fn -> live(conn, base <> "/pull-requests/99") end
    assert_raise NotFoundError, fn -> live(conn, base <> "/pull-requests/not-a-number") end
  end
end
