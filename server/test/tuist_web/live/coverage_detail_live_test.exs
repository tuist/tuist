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
    # The pages read the last 30 days by default, so the commits are recent.
    yesterday = DateTime.add(DateTime.utc_now(), -1, :day)

    CoverageFixtures.seed_history(organization.account, [
      CoverageFixtures.commit("a", [], 0, yesterday),
      CoverageFixtures.commit("b", ["a"], 1, yesterday)
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
    assert lv |> element("#coverage-detail [data-part='status']") |> render() =~ "In Progress"
    refute has_element?(lv, "[data-part='files-coverage']")

    Commits.signal_complete(project, "b")

    # A complete commit's page carries no status badge: only one still in
    # progress says so.
    {:ok, lv, _html} = live(conn, base <> "/commits/b")
    refute has_element?(lv, "#coverage-detail [data-part='status']")
  end

  test "says a figure is incomplete in the status once its pipeline finished, not in a banner", %{
    conn: conn,
    base: base,
    organization: organization,
    project: project
  } do
    CoverageFixtures.run_with_coverage(project, organization.account, [file("Sources/A.swift", [1, 0])], %{
      git_commit_sha: "a",
      partial: true
    })

    # More runs may still land, so it is in progress first.
    {:ok, lv, _html} = live(conn, base <> "/commits/a")
    assert lv |> element("#coverage-detail [data-part='status']") |> render() =~ "In Progress"

    for sha <- ~w(a b), do: Commits.signal_complete(project, sha)

    # A selective run whose skipped tests nothing listed: their coverage is unknown.
    {:ok, lv, _html} = live(conn, base <> "/commits/a")
    assert lv |> element("#coverage-detail [data-part='status']") |> render() =~ "Incomplete"
    refute has_element?(lv, ".noora-alert")

    {:ok, lv, _html} = live(conn, base <> "/commits/b")
    refute has_element?(lv, "#coverage-detail [data-part='status']")

    # Lists say it in the status, and have no change for it.
    {:ok, lv, _html} = live(conn, base <> "/branches/main?tab=commits")
    assert has_element?(lv, "#coverage-commit-status-a", "Incomplete")
    assert has_element?(lv, "#coverage-commit-status-b", "Complete")

    {:ok, lv, _html} = live(conn, base <> "/branches/main?tab=commits&commits-status=incomplete")
    assert has_element?(lv, "#coverage-commit-status-a")
    refute has_element?(lv, "#coverage-commit-status-b")
  end

  test "lists a run from a dirty checkout as discarded, and says why the commit is incomplete", %{
    conn: conn,
    base: base,
    organization: organization,
    project: project
  } do
    # Lands after the commit's clean run, and still folds it.
    dirty =
      CoverageFixtures.run_with_coverage(project, organization.account, [file("Sources/C.swift", [1, 1])], %{
        git_commit_sha: "b",
        scheme: "AppTests",
        git_dirty: true
      })

    Commits.signal_complete(project, "b")

    {:ok, lv, _html} = live(conn, base <> "/commits/b")
    status = lv |> element("#coverage-detail [data-part='badges']") |> render()
    assert status =~ "Incomplete"
    assert status =~ "uncommitted changes"
    assert has_element?(lv, "#widget-coverage", "66.7%")

    {:ok, lv, _html} = live(conn, base <> "/commits/b?tab=runs")
    assert has_element?(lv, "#coverage-run-kind-#{dirty.id}", "Discarded")
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

  test "opens a file of the commit on its own page, at that commit", %{conn: conn, base: base} do
    {:ok, lv, _html} = live(conn, base <> "/commits/b?tab=files")
    from = URI.encode_www_form("#{base}/commits/b?tab=files")
    assert has_element?(lv, "#coverage-files-table a[href='#{base}/files/Sources/A.swift?commit=b&from=#{from}']")

    {:ok, lv, _html} = live(conn, base <> "/files/Sources/A.swift?commit=b&from=#{from}")
    assert has_element?(lv, "[data-part='back-button'][href='#{base}/commits/b?tab=files']", "Commit b")
    assert has_element?(lv, "#coverage-file-page [data-part='badges'] [data-part='commit']", "b")
    assert has_element?(lv, "[data-part='file-summary-card']", "Analytics")
    assert has_element?(lv, "#widget-coverage-file-percentage", "50.0%")
    assert has_element?(lv, "#widget-coverage-file-lines", "2 / 4")
    refute has_element?(lv, "#coverage-chart")
    refute has_element?(lv, "#coverage-branch-dropdown")
    refute has_element?(lv, "#coverage-date-range-picker")

    # It links to the same file without a commit, on the default branch.
    assert has_element?(lv, "[data-part='file-link'][href='#{base}/files/Sources/A.swift']", "File: A.swift")

    # Without `from` it leads to the commit's files.
    {:ok, lv, _html} = live(conn, base <> "/files/Sources/A.swift?commit=b")
    assert has_element?(lv, "[data-part='back-button'][href='#{base}/commits/b?tab=files']", "Commit b")

    {:ok, lv, _html} = live(conn, base <> "/files/Sources/Missing.swift?commit=b")
    assert has_element?(lv, "[data-part='file-empty']", "Commit b has no coverage for this file")
  end

  test "is not found for a commit without coverage", %{conn: conn, base: base} do
    assert_raise NotFoundError, fn -> live(conn, base <> "/commits/nothing") end
  end

  describe "a branch" do
    test "reads as its head commit, with its trend over the period, its commits and its runs", %{
      conn: conn,
      base: base,
      run: run,
      project: project
    } do
      # Its chart reads complete commits only, as the Code Coverage page's does.
      {:ok, lv, _html} = live(conn, base <> "/branches/main")
      refute has_element?(lv, "#coverage-chart")

      Commits.signal_complete(project, "b")
      {:ok, lv, _html} = live(conn, base <> "/branches/main")
      chart = lv |> element("#coverage-chart") |> render()
      assert chart =~ "&quot;dateFormat&quot;:&quot;minute&quot;"
      # A point opens its commit, leading back to the branch.
      assert chart =~ "/tests/coverage/commits/b?from=#{URI.encode_www_form("#{base}/branches/main")}"

      assert has_element?(lv, "h1[aria-label='Branch main']", "main")
      assert has_element?(lv, "[data-part='kind'][data-kind='branch']")
      # Only a commit's page says whether its pipeline finished.
      refute has_element?(lv, "#coverage-detail [data-part='status']")
      assert has_element?(lv, "#widget-coverage", "66.7%")
      assert has_element?(lv, "#coverage-chart")
      assert has_element?(lv, "[data-part='analytics'] #coverage-analytics-date-range-picker")
      refute has_element?(lv, "[data-part='analytics']", "Default Branch Analytics: main")
      assert render(lv) =~ "?tab=commits"

      {:ok, lv, _html} = live(conn, base <> "/branches/main?tab=commits")
      assert has_element?(lv, "[data-part='commits-table'] .tuist-pagination button[disabled]", "Prev")
      assert has_element?(lv, "#coverage-commits-table thead", "Change")
      from = URI.encode_www_form("#{base}/branches/main?tab=commits")
      assert has_element?(lv, "#coverage-commits-table a[href$='/tests/coverage/commits/b?from=#{from}']")

      # The commit, and a file of it, lead back to the branch as it was.
      {:ok, lv, _html} = live(conn, base <> "/commits/b?from=#{from}")
      assert has_element?(lv, "[data-part='back-button'][href='#{base}/branches/main?tab=commits']", "Branch main")

      {:ok, lv, _html} = live(conn, base <> "/files/Sources/A.swift?commit=b&from=#{from}")
      assert has_element?(lv, "[data-part='back-button'][href='#{base}/branches/main?tab=commits']", "Branch main")

      # Anywhere else is not somewhere to lead back to.
      {:ok, lv, _html} = live(conn, base <> "/commits/b?from=" <> URI.encode_www_form("https://example.com/x"))
      assert has_element?(lv, "[data-part='back-button'][href='#{base}']", "Code Coverage")

      {:ok, lv, _html} = live(conn, base <> "/branches/main?tab=runs")
      assert has_element?(lv, "#coverage-runs-table a[href$='/tests/test-runs/#{run.id}']")
    end

    test "opens its files on their own page, over the branch and the period shown", %{
      conn: conn,
      base: base,
      organization: organization,
      project: project
    } do
      CoverageFixtures.run_with_coverage(project, organization.account, [file("Sources/A.swift", [1, 0, 0, 0])], %{
        git_commit_sha: "a",
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600)
      })

      for sha <- ~w(a b), do: Commits.signal_complete(project, sha)
      %{points: points} = History.trend_points(project, "main")

      assert Enum.map(History.file_points(project, "Sources/A.swift", points), &{&1.git_commit_sha, &1.coverage}) ==
               [{"a", 25.0}, {"b", 50.0}]

      {:ok, lv, _html} = live(conn, base <> "/branches/main?tab=files&coverage-date-range=last-7-days")

      href =
        lv
        |> element("#coverage-files-table")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.attribute("a[href*='/files/Sources/A.swift']", "href")
        |> List.first()

      assert URI.decode_query(URI.parse(href).query) == %{
               "branch" => "main",
               "coverage-date-range" => "last-7-days",
               "from" => base <> "/branches/main?coverage-date-range=last-7-days&tab=files"
             }
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

  test "a commit has no commits tab of its own", %{conn: conn, base: base} do
    {:ok, lv, _html} = live(conn, base <> "/commits/b")
    refute render(lv) =~ "tab=commits"

    {:ok, lv, _html} = live(conn, base <> "/commits/b?tab=commits")
    assert has_element?(lv, "[data-part='summary-card']")
  end

  test "is not found for a branch without coverage", %{conn: conn, base: base} do
    assert_raise NotFoundError, fn -> live(conn, base <> "/branches/nothing") end
  end

  test "has no pull request page", %{conn: conn, base: base} do
    assert conn |> get(base <> "/pull-requests/7") |> Map.fetch!(:status) == 404
  end
end
