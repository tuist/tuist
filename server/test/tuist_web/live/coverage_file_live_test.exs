defmodule TuistWeb.CoverageFileLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  alias Tuist.Tests.Coverage.Commits
  alias TuistTestSupport.Fixtures.CoverageFixtures

  defp file(path, counts), do: CoverageFixtures.file(path, counts, targets: ["Calculator"])

  # A run of the branch, its commit signalled complete unless
  # `complete: false` says otherwise.
  defp run(project, organization, sha, files, attrs \\ %{}) do
    {complete, attrs} = Map.pop(attrs, :complete, true)

    CoverageFixtures.run_with_coverage(
      project,
      organization.account,
      files,
      Map.merge(%{git_commit_sha: sha, ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600, :second)}, attrs)
    )

    if complete, do: Commits.signal_complete(project, sha)
  end

  setup %{organization: organization, project: project} do
    %{base: ~p"/#{organization.account.name}/#{project.name}/tests/coverage"}
  end

  test "reads the file at the branch's latest complete commit in the period, with its trend", %{
    conn: conn,
    base: base,
    organization: organization,
    project: project
  } do
    run(project, organization, "a", [file("Sources/A.swift", [1, 0, 0, 0])], %{
      ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -7200, :second)
    })

    run(project, organization, "b", [file("Sources/A.swift", [1, 1, 0, 0])])

    run(project, organization, "pending", [file("Sources/A.swift", [1, 1, 1, 1])], %{
      ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60, :second),
      complete: false
    })

    {:ok, lv, _html} = live(conn, base <> "/files/Sources/A.swift")

    assert has_element?(lv, "[data-part='title'] h1[data-part='label']", "A.swift")
    assert has_element?(lv, "#coverage-file-page > [data-part='header'] #coverage-date-range-picker")
    refute has_element?(lv, "#coverage-branch-dropdown")
    assert has_element?(lv, "#widget-coverage", "50.0%")
    assert has_element?(lv, "#widget-coverage-covered-lines", "2")
    assert has_element?(lv, "#widget-coverage-executable-lines", "4")
    assert has_element?(lv, "#widget-coverage [data-part='trend']", "+25.0%")
    assert render(element(lv, "#coverage-chart")) =~ "&quot;dateFormat&quot;:&quot;minute&quot;"
    assert has_element?(lv, "[data-part='back-button'][href='#{base}']", "Code coverage")
  end

  test "reads the branch the address names, and the period it picks", %{
    conn: conn,
    base: base,
    organization: organization,
    project: project
  } do
    run(project, organization, "m", [file("Sources/A.swift", [1, 0])])

    run(project, organization, "r", [file("Sources/A.swift", [1, 1])], %{
      git_branch: "release",
      ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -10, :day)
    })

    path = base <> "/files/Sources/A.swift?branch=release&coverage-date-range=last-30-days"
    {:ok, lv, _html} = live(conn, path)
    assert has_element?(lv, "#widget-coverage", "100.0%")

    assert has_element?(
             lv,
             "[data-part='back-button'][href='#{base}?branch=release&coverage-date-range=last-30-days']"
           )

    lv
    |> element("#coverage-date-range-picker")
    |> render_hook("coverage_period_changed", %{"value" => %{"start" => "", "end" => ""}, "preset" => "last-7-days"})

    assert_patch(lv, base <> "/files/Sources/A.swift?branch=release&coverage-date-range=last-7-days")
    assert has_element?(lv, "[data-part='file-empty']")
  end

  test "leads back to the page it was opened from", %{
    conn: conn,
    base: base,
    organization: organization,
    project: project
  } do
    run(project, organization, "m", [file("Sources/A.swift", [1, 0])])
    from = base <> "/branches/main?tab=files"

    {:ok, lv, _html} = live(conn, base <> "/files/Sources/A.swift?" <> URI.encode_query(%{"from" => from}))
    assert has_element?(lv, "[data-part='back-button'][href='#{from}']", "Branch main")
  end

  test "says when the latest complete commit has no coverage for the file", %{
    conn: conn,
    base: base,
    organization: organization,
    project: project
  } do
    {:ok, lv, _html} = live(conn, base <> "/files/Sources/A.swift")
    assert has_element?(lv, "[data-part='file-empty']")

    run(project, organization, "m", [file("Sources/A.swift", [1, 0])])
    {:ok, lv, _html} = live(conn, base <> "/files/Sources/Missing.swift")
    assert has_element?(lv, "[data-part='file-empty']", "has no coverage for this file")
    refute has_element?(lv, "#coverage-functions-table")
  end

  test "is found by a path with slashes, encoded or not", %{
    conn: conn,
    base: base,
    organization: organization,
    project: project
  } do
    run(project, organization, "m", [file("Sources/Deep/A.swift", [1, 0])])

    for path <- ["/files/Sources/Deep/A.swift", "/files/Sources%2FDeep%2FA.swift"] do
      {:ok, lv, _html} = live(conn, base <> path)
      assert has_element?(lv, "#widget-coverage", "50.0%")
      assert has_element?(lv, "#coverage-file-page [data-part='badges']", "Sources/Deep")
    end
  end

  test "searches, sorts and pages the file's functions, least covered first by default", %{
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
    run(project, organization, "m", [file])
    path = base <> "/files/Sources/F.swift"

    {:ok, lv, _html} = live(conn, path)
    rows = lv |> element("#coverage-functions-table tbody") |> render()
    assert :binary.match(rows, "zeta()") < :binary.match(rows, "helper1()")
    assert has_element?(lv, "#coverage-functions-sort-by-label-portal", "Coverage")
    refute has_element?(lv, "#coverage-functions-table", "helper20()")

    {:ok, lv, _html} = live(conn, path <> "?page=2")
    assert has_element?(lv, "#coverage-functions-table", "helper20()")

    {:ok, lv, _html} = live(conn, path <> "?functions-sort-by=name&functions-sort-order=desc")
    rows = lv |> element("#coverage-functions-table tbody") |> render()
    assert :binary.match(rows, "zeta()") < :binary.match(rows, "helper9()")

    # Most executed first: the one function that never ran is the 21st, on the second page.
    {:ok, lv, _html} = live(conn, path <> "?functions-sort-by=executions")
    assert has_element?(lv, "#coverage-functions-sort-by-label-portal", "Executions")
    refute has_element?(lv, "#coverage-functions-table", "zeta()")

    {:ok, lv, _html} = live(conn, path <> "?functions-sort-by=line&functions-sort-order=desc")
    rows = lv |> element("#coverage-functions-table tbody") |> render()
    assert :binary.match(rows, "zeta()") < :binary.match(rows, "helper20()")

    {:ok, lv, _html} = live(conn, path <> "?functions-sort-by=covered_lines&functions-sort-order=asc")
    rows = lv |> element("#coverage-functions-table tbody") |> render()
    assert :binary.match(rows, "zeta()") < :binary.match(rows, "helper1()")

    lv |> form("#coverage-functions-search-form", %{search: "ZETA"}) |> render_change()
    assert has_element?(lv, "#coverage-functions-table", "zeta()")
    refute has_element?(lv, "#coverage-functions-table", "helper1()")

    {:ok, lv, _html} = live(conn, path <> "?functions-search=missing")
    assert has_element?(lv, "#coverage-functions-table", "No function matches this search")
  end
end
