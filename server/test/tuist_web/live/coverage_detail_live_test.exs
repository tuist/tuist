defmodule TuistWeb.CoverageDetailLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Tuist.Tests.Coverage.Commits
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

    assert has_element?(lv, "#widget-coverage", "66.7%")
    assert has_element?(lv, "#widget-covered-lines", "4")
    assert has_element?(lv, "#widget-executable-lines", "6")
    refute has_element?(lv, ".noora-alert")
    assert lv |> element("#coverage-detail [data-part='status']") |> render() =~ "Pending"
    assert has_element?(lv, "#coverage-gap-files-table", "A.swift")

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
  end

  test "opens a file of the commit on its own page, with its uncovered lines", %{conn: conn, base: base} do
    {:ok, lv, _html} = live(conn, base <> "/commits/b")
    assert has_element?(lv, "#coverage-gap-files-table a[href='#{base}/files/Sources/A.swift?commit=b&tab=overview']")

    {:ok, lv, _html} = live(conn, base <> "/files/Sources/A.swift?commit=b&tab=overview")
    assert has_element?(lv, "[data-part='back-button'][href='#{base}/commits/b?tab=overview']")
    assert has_element?(lv, "#widget-coverage-file-percentage", "50.0%")
    assert has_element?(lv, "#coverage-file-targets li", "Calculator")
    assert has_element?(lv, "#coverage-file-uncovered-lines", "3–4")

    {:ok, lv, _html} = live(conn, base <> "/files/Sources/Missing.swift?commit=b")
    assert has_element?(lv, "[data-part='file-empty']")
  end

  test "is not found for a commit without coverage", %{conn: conn, base: base} do
    assert_raise NotFoundError, fn -> live(conn, base <> "/commits/nothing") end
    assert_raise NotFoundError, fn -> live(conn, base <> "/files/Sources/A.swift?commit=nothing") end
  end
end
