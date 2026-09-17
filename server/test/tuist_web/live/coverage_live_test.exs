defmodule TuistWeb.CoverageLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.GitHistory
  alias Tuist.Projects
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

  defp pr_run(project, organization, files, attrs \\ %{}) do
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

  defp seed_history(project) do
    GitHistory.record_commits(project.id, "sha1", [
      %{sha: "a", parents: [], committed_at: ~U[2026-09-01 00:00:00Z]},
      %{sha: "b", parents: ["a"], committed_at: ~U[2026-09-01 01:00:00Z]},
      %{sha: "p", parents: ["b"], committed_at: ~U[2026-09-01 02:00:00Z]}
    ])
  end

  describe "overview" do
    test "shows the default branch's newest full run and its trend over the period", %{
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
      assert has_element?(lv, "#widget-coverage-baseline", "b")
      assert has_element?(lv, "#coverage-chart")
      assert has_element?(lv, "#coverage-points-table", "a")
      refute has_element?(lv, "#coverage-points-table", "c")
    end

    test "shows the empty state without a full run and hides the page without the flag", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")
      assert has_element?(lv, "[data-part='empty-overview']")

      stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)

      assert_raise NotFoundError, fn ->
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage")
      end
    end
  end

  describe "branches" do
    test "lists every branch's newest full run against the default branch", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      main_run(project, organization, "b", [file("Sources/A.swift", [1, 1, 0, 0])])
      main_run(project, organization, "f", [file("Sources/A.swift", [1, 1, 1, 0])], %{git_branch: "feature"})

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage?tab=branches")

      table = lv |> element("#coverage-branches-table") |> render()
      assert table =~ "feature"
      assert table =~ "+25.0 pp"
      assert table =~ "main"
    end
  end

  describe "pull requests" do
    setup %{organization: organization, project: project} do
      seed_history(project)
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

    test "lists the pull requests with their change against the baseline", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage?tab=pull-requests")

      table = lv |> element("#coverage-pull-requests-table") |> render()
      assert table =~ "#12"
      assert table =~ "50.0%"
      assert table =~ "-50.0 pp"
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

    test "says why there is no baseline", %{conn: conn, organization: organization, project: project} do
      pr_run(project, organization, [file("Sources/A.swift", [1, 1, 1, 1])], %{
        pull_request_number: 13,
        merge_base_sha: "zzz"
      })

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/pull-requests/13")

      assert has_element?(lv, "#coverage-no-baseline")
      assert lv |> element("#coverage-no-baseline") |> render() =~ "commit zzz is not in the project"
      assert has_element?(lv, "#widget-pr-change", "No baseline")
    end

    test "is not found for a pull request without coverage", %{conn: conn, organization: organization, project: project} do
      assert_raise NotFoundError, fn ->
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage/pull-requests/99")
      end
    end
  end

  describe "files and runs" do
    test "lists the least covered files and the targets of the newest full run", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      main_run(project, organization, "b", [file("Sources/A.swift", [1, 1, 0, 0]), file("Sources/B.swift", [1, 1])])

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage?tab=files")

      assert has_element?(lv, "#coverage-targets-table", "Calculator")
      files = lv |> element("#coverage-files-table") |> render()
      assert files =~ "Sources/A.swift"
      assert files =~ "Sources/B.swift"
    end

    test "lists the runs with coverage, narrowed by kind", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      main_run(project, organization, "b", [file("Sources/A.swift", [1, 1, 0, 0])])
      main_run(project, organization, "c", [file("Sources/A.swift", [1, 0, 0, 0])], %{partial: true, scheme: "Partial"})

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage?tab=runs")
      table = lv |> element("#coverage-runs-table") |> render()
      assert table =~ "50.0%"
      assert table =~ "25.0%"

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage?tab=runs&coverage=full")

      table = lv |> element("#coverage-runs-table") |> render()
      assert table =~ "50.0%"
      refute table =~ "25.0%"
    end
  end

  describe "settings" do
    test "the old settings tab leads to the project's coverage settings", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      path = ~p"/#{organization.account.name}/#{project.name}/settings/coverage"

      assert {:error, {:live_redirect, %{to: ^path}}} =
               live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/coverage?tab=settings")
    end
  end
end
