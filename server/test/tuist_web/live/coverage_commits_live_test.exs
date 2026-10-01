defmodule TuistWeb.CoverageCommitsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  alias Tuist.Tests.Coverage.Commits
  alias TuistTestSupport.Fixtures.CoverageFixtures

  defp file(path, counts), do: CoverageFixtures.file(path, counts, targets: ["Calculator"])

  defp run(project, organization, sha, counts, attrs \\ %{}) do
    {complete, attrs} = Map.pop(attrs, :complete, true)

    CoverageFixtures.run_with_coverage(
      project,
      organization.account,
      [file("Sources/A.swift", counts)],
      Map.merge(%{git_commit_sha: sha, ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600, :second)}, attrs)
    )

    if complete, do: Commits.signal_complete(project, sha)
  end

  defp commits_path(organization, project), do: ~p"/#{organization.account.name}/#{project.name}/tests/coverage/commits"

  defp shas(lv) do
    lv
    |> element("#coverage-commits-table")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("tbody tr td:first-child")
    |> Enum.map(&String.trim(Floki.text(&1)))
  end

  describe "a branch with history" do
    # main: a → b → c → d; a and c complete, b never measured, d pending.
    setup %{organization: organization, project: project} do
      yesterday = DateTime.add(DateTime.utc_now(), -1, :day)

      CoverageFixtures.seed_history(
        organization.account,
        for(
          {sha, index} <- Enum.with_index(~w(a b c d)),
          do: CoverageFixtures.commit(sha, ~w(a b c) |> Enum.take(index) |> Enum.take(-1), index, yesterday)
        ),
        branch_heads: [{"main", "d"}]
      )

      run(project, organization, "a", [1, 0, 0, 0])
      run(project, organization, "c", [1, 1, 1, 0])
      run(project, organization, "d", [1, 1, 0, 0], %{complete: false})
      :ok
    end

    test "lists every commit of the branch, newest first, whatever its status", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, commits_path(organization, project))

      assert shas(lv) == ~w(d c b a)
      assert has_element?(lv, "#coverage-commit-status-d", "In Progress")
      assert has_element?(lv, "#coverage-commit-status-c", "Complete")
      assert has_element?(lv, "#coverage-commit-status-b", "Not measured")
      assert has_element?(lv, "#coverage-commits-status-dropdown-label-portal", "Any")
    end

    test "narrows the commits by the start of their SHA and by status", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      path = commits_path(organization, project)
      {:ok, lv, _html} = live(conn, path)

      lv |> form("#coverage-commits-filter-form", %{"search" => "C"}) |> render_change()
      assert_patch(lv, path <> "?commits-search=C")
      assert shas(lv) == ["c"]

      {:ok, lv, _html} = live(conn, path <> "?commits-status=not-measured")
      assert shas(lv) == ["b"]
      assert has_element?(lv, "#coverage-commits-status-dropdown-label-portal", "Not measured")

      {:ok, lv, _html} = live(conn, path <> "?commits-search=zz")
      assert has_element?(lv, "[data-part='empty-commits']", "No commit matches these filters")
    end

    test "leads back to the Code Coverage page, keeping the branch and period, and links no commit", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      base = ~p"/#{organization.account.name}/#{project.name}/tests/coverage"
      query = "branch=main&coverage-date-range=last-7-days"
      {:ok, lv, _html} = live(conn, commits_path(organization, project) <> "?" <> query <> "&commits-status=complete")

      assert has_element?(lv, "[data-part='back-button'][href='#{base}?#{query}']")

      refute has_element?(lv, "#coverage-commits-table a")
    end
  end

  test "shows the selected branch's commits", %{conn: conn, organization: organization, project: project} do
    run(project, organization, "m", [1, 0])
    run(project, organization, "r", [1, 1], %{git_branch: "release"})

    {:ok, lv, _html} = live(conn, commits_path(organization, project) <> "?branch=release")

    assert shas(lv) == ["r"]

    assert lv |> element("#coverage-branch-dropdown-content-portal") |> render() =~
             ~s(href="?branch=main")
  end

  test "pages the commits from a cursor", %{conn: conn, organization: organization, project: project} do
    for index <- 1..21 do
      run(project, organization, "c#{index}", [1, 0], %{
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -index * 60, :second)
      })
    end

    {:ok, lv, _html} = live(conn, commits_path(organization, project))
    assert length(shas(lv)) == 20
    [_, cursor] = Regex.run(~r/after=([^"&]+)/, render(lv))

    {:ok, lv, _html} = live(conn, commits_path(organization, project) <> "?after=" <> cursor)
    assert shas(lv) == ["c21"]
  end

  test "says when the branch has no commit in the period", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _html} = live(conn, commits_path(organization, project))

    assert has_element?(
             lv,
             "[data-part='back-button'][href='/#{organization.account.name}/#{project.name}/tests/coverage']"
           )

    assert has_element?(lv, "[data-part='empty-commits']", "No commits on main in this period")
  end
end
