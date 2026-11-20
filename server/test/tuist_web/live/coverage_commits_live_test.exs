defmodule TuistWeb.CoverageCommitsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Tests.Coverage.Commits
  alias TuistTestSupport.Fixtures.CoverageFixtures

  defp file(path, counts), do: CoverageFixtures.file(path, counts, targets: ["Calculator"])

  defp run(project, organization, sha, counts, hours_ago, attrs \\ %{}) do
    CoverageFixtures.run_with_coverage(
      project,
      organization.account,
      [file("Sources/A.swift", counts)],
      Map.merge(
        %{git_commit_sha: sha, ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -hours_ago * 3600, :second)},
        attrs
      )
    )
  end

  defp rows(lv) do
    lv
    |> element("#coverage-commits-table")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("tbody tr")
    |> Enum.map(fn row ->
      [commit, branch, coverage, status] = row |> Floki.find("td") |> Enum.take(4)
      # The status cell also holds its tooltip; its badge is the status.
      Enum.map([commit, branch, coverage], &text/1) ++ [status |> Floki.find(".noora-badge") |> text()]
    end)
  end

  defp text(node), do: node |> Floki.text(sep: " ") |> String.split() |> Enum.join(" ")

  test "lists every measured commit, whatever its branch or status, the most recently run first", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    run(project, organization, "aaaaaaa1", [1, 1, 0, 0], 4)
    Commits.signal_complete(project, "aaaaaaa1")
    run(project, organization, "bbbbbbb2", [1, 1, 1, 0], 3)

    run(project, organization, "ccccccc3", [1, 1, 1, 1], 2, %{
      git_branch: "feature/gates",
      is_pull_request: true,
      pull_request_number: 42,
      base_branch: "main"
    })

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/commits")

    assert rows(lv) == [
             ["ccccccc", "feature/gates Pull request #42", "100.0%", "In Progress"],
             ["bbbbbbb", "main", "75.0%", "In Progress"],
             ["aaaaaaa", "main", "50.0%", "Complete"]
           ]
  end

  test "lists a commit only dirty CI runs measured as incomplete", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    run(project, organization, "aaaaaaa1", [1, 0], 3)
    run(project, organization, "ddddddd4", [1, 1], 2, %{git_dirty: true})

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/commits")

    assert rows(lv) == [
             ["ddddddd", "main", "0.0%", "In Progress"],
             ["aaaaaaa", "main", "50.0%", "In Progress"]
           ]
  end

  test "opens a commit's page, whose back button leads here", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    run(project, organization, "aaaaaaa1", [1, 0], 1)
    path = ~p"/#{organization.account.name}/#{project.name}/tests/coverage/commits"

    {:ok, lv, _html} = live(conn, path)

    href =
      ~p"/#{organization.account.name}/#{project.name}/tests/coverage/commits/aaaaaaa1" <>
        "?" <> URI.encode_query(%{"from" => path})

    assert lv |> element("#coverage-commits-table") |> render() =~
             href |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    {:ok, commit, _html} = live(conn, href)
    assert has_element?(commit, ~s([data-part='back-button'][href="#{path}"]), "Recent Commits")
  end

  test "says when no run gathered coverage", %{conn: conn, organization: organization, project: project} do
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/commits")

    assert has_element?(lv, "[data-part='empty-commits']", "No run gathered coverage yet")
    refute has_element?(lv, "#coverage-commits-table")
  end
end
