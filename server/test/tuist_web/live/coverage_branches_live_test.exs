defmodule TuistWeb.CoverageBranchesLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Tests.Coverage.Commits
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

  defp pr_run(project, organization, files, attrs) do
    CoverageFixtures.run_with_coverage(
      project,
      organization.account,
      files,
      Map.merge(
        %{
          git_branch: "feature",
          git_commit_sha: "p",
          base_branch: "main",
          merge_base_sha: "b",
          is_pull_request: true,
          pull_request_number: 12,
          history_source: "client",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60, :second)
        },
        attrs
      )
    )
  end

  defp seed_history(organization, opts \\ []) do
    CoverageFixtures.seed_history(
      organization.account,
      [
        CoverageFixtures.commit("a", [], 0),
        CoverageFixtures.commit("b", ["a"], 1),
        CoverageFixtures.commit("c", ["b"], 2),
        CoverageFixtures.commit("p", ["b"], 3)
      ],
      opts
    )
  end

  describe "the branches index" do
    test "lists every branch against the default branch and narrows it by search", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      main_run(project, organization, "b", [file("Sources/A.swift", [1, 1, 0, 0])])
      main_run(project, organization, "f", [file("Sources/A.swift", [1, 1, 1, 0])], %{git_branch: "feature"})

      pr_run(project, organization, [file("Sources/A.swift", [1, 1, 1, 1])], %{
        git_commit_sha: "r",
        pull_request_number: 21
      })

      # `feature` and pull request 21 are the same branch, so the list holds
      # one row for them.

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/branches")

      table = lv |> element("#coverage-branches-table") |> render()
      # The branch is listed once, carrying the pull request it was pushed
      # for and its newest measured commit.
      assert table =~ "feature"
      assert table =~ "#21"
      assert table =~ "main"
      assert has_element?(lv, "#coverage-branches-table a[href*='/tests/coverage/pull-requests/21']")
      # A branch without a pull request leads to its own page.
      assert has_element?(lv, "#coverage-branches-table a[href*='/tests/coverage/branches/main']")

      lv |> form("#coverage-branches-filter-form", search: "#21") |> render_change()

      table = lv |> element("#coverage-branches-table") |> render()
      assert table =~ "#21"
      refute table =~ ~s(id="ref-main")
    end
  end
end
