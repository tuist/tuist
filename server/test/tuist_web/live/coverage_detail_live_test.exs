defmodule TuistWeb.CoverageDetailLiveTest do
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

      assert has_element?(lv, "#widget-coverage", "50.0%")
      assert has_element?(lv, "#widget-change", "-50.0%")
      assert has_element?(lv, "#widget-patch", "0.0%")
      assert has_element?(lv, "#widget-gaps", "2")
      # A pull request has a diff, so it is judged on it rather than read as a whole.
      refute has_element?(lv, "#widget-covered-lines")
      refute has_element?(lv, "#widget-files-without-data")
      refute has_element?(lv, "#coverage-no-baseline")
      assert has_element?(lv, "#coverage-incomplete")

      # Where coverage moved is a highlight on the overview; the full lists
      # live in their own tabs.
      falls = lv |> element("#coverage-target-falls-table") |> render()
      assert falls =~ "Calculator"
      assert falls =~ "-50.0%"

      patch = lv |> element("#coverage-patch-table") |> render()
      assert patch =~ "Sources/A.swift"
      assert patch =~ "Sources/New.swift"
      assert patch =~ "3–4"

      skipped = lv |> element("#coverage-skipped-table") |> render()
      assert skipped =~ "README.md"
      assert skipped =~ "Not compiled into any tested target"

      # The runs that measured it are a tab of their own.
      {:ok, runs_lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/coverage/pull-requests/12?tab=runs"
        )

      assert has_element?(runs_lv, "a[href*='/tests/test-runs/#{pr.id}?tab=coverage']")

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/coverage/pull-requests/12?tab=targets"
        )

      targets = lv |> element("#coverage-targets-table") |> render()
      assert targets =~ "Calculator"
      assert targets =~ "-50.0%"

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/coverage/pull-requests/12?tab=files"
        )

      files = lv |> element("#coverage-files-table") |> render()
      assert files =~ "A.swift"
      assert files =~ "New.swift"
      refute files =~ "B.swift"
    end

    test "lists the pull request's commits in their own tab", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/coverage/pull-requests/12?tab=commits"
        )

      commits = lv |> element("#coverage-commits-table") |> render()
      assert commits =~ "p"
      assert has_element?(lv, "#coverage-commits-table a[href*='/tests/coverage/commits/p']")
    end

    test "charts a pull request's commits once it has more than one", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      pr_run(project, organization, [file("Sources/A.swift", [1, 1, 1, 0])], %{
        git_commit_sha: "p2",
        ran_at: NaiveDateTime.utc_now()
      })

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/pull-requests/12")

      assert has_element?(lv, "#coverage-detail-chart")
    end

    test "reads a branch as its head commit, with its commits and its distance from the default branch",
         %{conn: conn, organization: organization, project: project} do
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/branches/main")

      assert has_element?(lv, "#widget-coverage", "100.0%")
      # The default branch is what the others are measured against, so it has
      # no distance of its own.
      refute has_element?(lv, "#widget-against-default")
      # A push to a branch has no diff to judge, so the page reads the commit
      # as a whole instead of showing an empty patch.
      refute has_element?(lv, "#widget-patch")
      refute has_element?(lv, "#widget-gaps")
      assert has_element?(lv, "#widget-covered-lines")
      assert has_element?(lv, "#widget-files-without-data")

      render_hook(lv, "coverage_period_changed", %{
        "preset" => "last-7-days",
        "value" => %{"start" => "2026-01-01T00:00:00.000Z", "end" => "2026-01-08T00:00:00.000Z"}
      })

      assert_patch(
        lv,
        ~p"/#{organization.account.name}/#{project.name}/tests/coverage/branches/main?coverage-date-range=last-7-days"
      )

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/coverage/branches/main?tab=commits"
        )

      assert lv |> element("#coverage-commits-table") |> render() =~ "b"

      assert_raise NotFoundError, fn ->
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/branches/nothing")
      end
    end

    test "measures a branch other than the default one against it", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      CoverageFixtures.run_with_coverage(
        project,
        organization.account,
        [file("Sources/A.swift", [1, 1, 1, 0])],
        %{git_commit_sha: "c", git_branch: "release/1.0"}
      )

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/branches/release/1.0")

      assert has_element?(lv, "#widget-coverage", "75.0%")
      assert has_element?(lv, "#widget-against-default", "-25.0%")
    end

    test "shows a commit on its own page, complete once signalled", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/commits/p")

      assert has_element?(lv, "#widget-coverage", "50.0%")
      assert has_element?(lv, "#coverage-incomplete")

      Commits.signal_complete(project, "p")

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/commits/p")
      refute has_element?(lv, "#coverage-incomplete")
      assert lv |> element("#coverage-detail [data-part='badges']") |> render() =~ "Complete"
    end

    test "opens a file of the commit with its uncovered lines and the tests behind it", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      main_run(project, organization, "b", [file("Sources/A.swift", [1, 1, 1, 0])], %{
        test_modules: [
          %{
            name: "AppTests",
            status: "success",
            duration: 1,
            test_cases: [%{name: "testA()", test_suite_name: "ATests", status: "success", duration: 1}]
          }
        ],
        coverage_evidence: %{
          paths: ["Sources/A.swift"],
          scopes: [%{kind: "test", module: "AppTests", suite: "ATests", name: "testA()", files: [0], lines: [[1, 3]]}]
        }
      })

      path = ~p"/#{organization.account.name}/#{project.name}/tests/coverage/commits/b"
      {:ok, lv, _html} = live(conn, path)
      refute has_element?(lv, "#coverage-file")

      {:ok, lv, _html} = live(conn, path <> "?coverage-file=Sources/A.swift")
      assert has_element?(lv, "#widget-coverage-file-percentage", "100.0%")
      assert has_element?(lv, "#coverage-file-uncovered-lines", "None")
      assert has_element?(lv, "#coverage-file-tests-table", "testA()")
      assert has_element?(lv, "#coverage-file-tests-table", "1–3")

      {:ok, lv, _html} = live(conn, path <> "?coverage-file=Sources/B.swift")
      assert has_element?(lv, "#coverage-file-no-tests")
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
      assert has_element?(lv, "#widget-change", "No baseline")
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
