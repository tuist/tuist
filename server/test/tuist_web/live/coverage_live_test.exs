defmodule TuistWeb.CoverageLiveTest do
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

  describe "analytics" do
    test "shows the latest chained commit of the branch, its trend and its gaps", %{
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
      assert has_element?(lv, "#widget-coverage-unmeasured-files", "0")
      assert has_element?(lv, "#coverage-chart")
    end

    test "leads to the branch's page over the same period", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      main_run(project, organization, "a", [file("Sources/A.swift", [1, 0, 0, 0])])

      base = ~p"/#{organization.account.name}/#{project.name}/tests/coverage"
      {:ok, lv, _html} = live(conn, base <> "?coverage-date-range=last-12-months")

      assert has_element?(
               lv,
               "[data-part='analytics'] a[href='#{base}/branches/main?coverage-date-range=last-12-months&tab=overview']"
             )

      assert has_element?(
               lv,
               "[data-part='commits'] a[href='#{base}/branches/main?coverage-date-range=last-12-months&tab=commits']"
             )
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
      # Nothing to see more of: the branch's page has no measured commit to open on.
      refute has_element?(lv, "[data-part='analytics'] a", "View more")
      refute has_element?(lv, "[data-part='commits'] a", "View more")

      stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)

      assert_raise NotFoundError, fn ->
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")
      end
    end
  end

  describe "commits" do
    test "lists the branch's commits from the graph, unmeasured ones included", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      seed_history(organization, branch_heads: [{"main", "c"}])
      main_run(project, organization, "a", [file("Sources/A.swift", [1, 0, 0, 0])])
      main_run(project, organization, "c", [file("Sources/A.swift", [1, 1, 1, 0])])

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")

      table = lv |> element("#coverage-commits-table") |> render()
      assert table =~ "Not measured"
      assert table =~ "+50.0%"
      # Each status explains itself on hover.
      assert table =~ "No run of this commit gathered coverage, so it has no figure of its own."
      refute has_element?(lv, "#coverage-commits-time-order")
      assert has_element?(lv, "#coverage-commits-table a[href*='/tests/coverage/commits/c']")
    end

    test "says when the commits could only be ordered by when they were measured", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      main_run(project, organization, "b", [file("Sources/A.swift", [1, 1, 0, 0])])

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")

      assert has_element?(lv, "#coverage-commits-time-order")
    end
  end

  describe "coverage gaps" do
    test "lists the least covered files and the files without coverage data", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      CoverageFixtures.seed_listing(organization.account, "b", [
        "Sources/A.swift",
        "Sources/B.swift",
        "Sources/Untested.swift"
      ])

      main_run(project, organization, "b", [file("Sources/A.swift", [1, 1, 0, 0]), file("Sources/B.swift", [1, 1])])

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")

      files = lv |> element("#coverage-gap-files-table") |> render()
      assert files =~ "A.swift"
      assert files =~ "50.0%"

      assert has_element?(
               lv,
               "#coverage-gap-files-table a[href='/#{organization.account.name}/#{project.name}/tests/coverage/files/Sources/A.swift?commit=b&branch=main&tab=overview']"
             )

      unmeasured = lv |> element("#coverage-unmeasured-files-table") |> render()
      assert unmeasured =~ "Untested.swift"
      refute unmeasured =~ "B.swift"
      assert has_element?(lv, "#widget-coverage-unmeasured-files", "1")
    end

    test "the Files tab pages the files without coverage data under their own parameter", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      untested = for index <- 1..25, do: "Sources/Untested#{String.pad_leading("#{index}", 2, "0")}.swift"
      CoverageFixtures.seed_listing(organization.account, "b", ["Sources/A.swift" | untested])
      main_run(project, organization, "b", [file("Sources/A.swift", [1, 1, 0, 0])])

      path = ~p"/#{organization.account.name}/#{project.name}/tests/coverage/branches/main"
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
