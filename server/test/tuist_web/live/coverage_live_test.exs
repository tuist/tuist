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

    test "shows the empty state without a measured commit and hides the page without the flag", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")
      assert has_element?(lv, "[data-part='empty-analytics']")
      assert has_element?(lv, "[data-part='empty-refs']")

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
      assert table =~ "+50.0 pp"
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
    test "lists the least covered files and the files nothing measured", %{
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

      unmeasured = lv |> element("#coverage-unmeasured-files-table") |> render()
      assert unmeasured =~ "Untested.swift"
      refute unmeasured =~ "B.swift"
      assert has_element?(lv, "#widget-coverage-unmeasured-files", "1")
    end
  end

  describe "branches and pull requests" do
    test "lists both against the default branch and narrows them by search", %{
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

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")

      table = lv |> element("#coverage-refs-table") |> render()
      # The branch is listed once, carrying the pull request it was pushed
      # for and its newest measured commit.
      assert table =~ "feature"
      assert table =~ "#21"
      assert table =~ "main"
      assert has_element?(lv, "#coverage-refs-table a[href*='/tests/coverage/pull-requests/21']")

      lv |> form("#coverage-refs-filter-form", search: "#21") |> render_change()

      table = lv |> element("#coverage-refs-table") |> render()
      assert table =~ "#21"
      refute table =~ ~s(id="ref-main")
    end
  end

  describe "a commit and a pull request" do
    setup %{organization: organization, project: project} do
      seed_history(organization)
      main_run(project, organization, "b", [file("Sources/A.swift", [1, 1, 1, 1]), file("Sources/B.swift", [1, 1])])

      pr =
        pr_run(
          project,
          organization,
          [file("Sources/A.swift", [1, 1, 0, 0]), file("Sources/B.swift", [1, 1]), file("Sources/New.swift", [0, 0])],
          %{
            changed_files: [
              %{
                path: "Sources/A.swift",
                status: "modified",
                git_blob_id: "blob-Sources/A.swift",
                hunks: [%{start: 3, end: 4}]
              },
              %{
                path: "Sources/New.swift",
                status: "added",
                git_blob_id: "blob-Sources/New.swift",
                hunks: [%{start: 1, end: 2}]
              },
              %{path: "README.md", status: "modified", git_blob_id: "r", hunks: [%{start: 1, end: 1}]}
            ]
          }
        )

      %{pr: pr}
    end

    test "shows a pull request's comparison, patch coverage and gaps", %{
      conn: conn,
      organization: organization,
      project: project,
      pr: pr
    } do
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/pull-requests/12")

      assert has_element?(lv, "#widget-pr-coverage", "50.0%")
      assert has_element?(lv, "#widget-pr-change", "-50.0 pp")
      assert has_element?(lv, "#widget-pr-patch", "0.0%")
      assert has_element?(lv, "#widget-pr-gaps", "2")
      refute has_element?(lv, "#coverage-no-baseline")
      assert has_element?(lv, "#coverage-incomplete")

      targets = lv |> element("#coverage-pr-targets-table") |> render()
      assert targets =~ "Calculator"
      assert targets =~ "-50.0 pp"

      patch = lv |> element("#coverage-pr-patch-table") |> render()
      assert patch =~ "Sources/A.swift"
      assert patch =~ "Sources/New.swift"
      assert patch =~ "3–4"

      skipped = lv |> element("#coverage-pr-skipped-table") |> render()
      assert skipped =~ "README.md"
      assert skipped =~ "Not compiled into any tested target"

      files = lv |> element("#coverage-pr-files-table") |> render()
      assert files =~ "Sources/A.swift"
      assert files =~ "Sources/New.swift"
      refute files =~ "Sources/B.swift"

      assert has_element?(lv, "a[href*='/tests/test-runs/#{pr.id}?tab=coverage']")
    end

    test "shows a commit on its own page, complete once signalled", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/commits/p")

      assert has_element?(lv, "#widget-pr-coverage", "50.0%")
      assert has_element?(lv, "#coverage-incomplete")

      Commits.signal_complete(project, "p")

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/commits/p")
      refute has_element?(lv, "#coverage-incomplete")
      assert lv |> element("#coverage-commit [data-part='subtitle']") |> render() =~ "Complete"
    end

    test "shows what the gates decided, and that they wait for the completion signal", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, project} =
        Tuist.Projects.update_project(project, %{
          coverage_gates_enabled: true,
          coverage_gate_min_patch_coverage: 80.0,
          coverage_gate_max_total_drop: 1.0
        })

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/commits/p")

      assert lv |> element("[data-part='verdict']") |> render() =~ "Pending"
      assert lv |> element("[data-part='verdict']") |> render() =~ "tuist coverage complete"

      gates = lv |> element("#coverage-gates-table") |> render()
      assert gates =~ "Minimum patch coverage"
      assert gates =~ "Maximum total drop"
      assert gates =~ "Failed"

      Commits.signal_complete(project, "p")

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/commits/p")
      assert lv |> element("[data-part='verdict']") |> render() =~ "Failed"
    end

    test "says why there is no baseline", %{conn: conn, organization: organization, project: project} do
      pr_run(project, organization, [file("Sources/A.swift", [1, 1, 1, 1])], %{
        pull_request_number: 13,
        git_commit_sha: "q",
        merge_base_sha: "zzz"
      })

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/pull-requests/13")

      assert has_element?(lv, "#coverage-no-baseline")
      assert lv |> element("#coverage-no-baseline") |> render() =~ "commit zzz is not in the repository"
      assert has_element?(lv, "#widget-pr-change", "No baseline")
    end

    test "is not found for a pull request or a commit without coverage", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      assert_raise NotFoundError, fn ->
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/pull-requests/99")
      end

      assert_raise NotFoundError, fn ->
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/commits/nothing")
      end
    end
  end
end
