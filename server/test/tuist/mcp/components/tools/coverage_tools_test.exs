defmodule Tuist.MCP.Components.Tools.CoverageToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.MCP.Components.Tools.GetCommitCoverage
  alias Tuist.MCP.Components.Tools.GetCommitCoverageComparison
  alias Tuist.MCP.Components.Tools.GetCommitCoverageFile
  alias Tuist.MCP.Components.Tools.GetPullRequestCoverage
  alias Tuist.MCP.Components.Tools.GetTestRunCoverage
  alias Tuist.MCP.Components.Tools.GetTestRunCoverageComparison
  alias Tuist.MCP.Components.Tools.GetTestRunCoverageFile
  alias Tuist.MCP.Components.Tools.ListCommitCoverageFiles
  alias Tuist.MCP.Components.Tools.ListCoverageBranches
  alias Tuist.MCP.Components.Tools.ListCoverageHistory
  alias Tuist.MCP.Components.Tools.ListTestRunCoverageFiles
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id, default_branch: "main")
    stub(Tuist.Authorization, :authorize, fn _action, _subject, _project -> :ok end)

    CoverageFixtures.seed_history(account, [CoverageFixtures.commit("b", [], 0), CoverageFixtures.commit("p", ["b"], 1)])

    base =
      CoverageFixtures.run_with_coverage(
        project,
        account,
        [CoverageFixtures.file("Sources/A.swift", [1, 1, 1, 1]), CoverageFixtures.file("Sources/B.swift", [1, 1])],
        %{git_commit_sha: "b", ran_at: ~N[2026-09-01 00:30:00]}
      )

    pr =
      CoverageFixtures.run_with_coverage(
        project,
        account,
        [CoverageFixtures.file("Sources/A.swift", [1, 1, 0, 0]), CoverageFixtures.file("Sources/B.swift", [1, 1])],
        %{
          git_branch: "feature",
          git_commit_sha: "p",
          base_branch: "main",
          merge_base_sha: "b",
          is_pull_request: true,
          pull_request_number: 5,
          history_source: "client",
          ran_at: ~N[2026-09-01 02:00:00],
          changed_files: [
            %{
              path: "Sources/A.swift",
              status: "modified",
              git_blob_id: "blob-Sources/A.swift",
              hunks: [%{start: 3, end: 4}]
            }
          ]
        }
      )

    %{conn: %Plug.Conn{assigns: %{current_subject: :subject}}, account: account, project: project, base: base, pr: pr}
  end

  defp call(tool, conn, args) do
    assert %{"content" => [%{"type" => "text", "text" => text}]} = result = tool.call(conn, args)
    refute Map.get(result, "isError"), text
    JSON.decode!(text)
  end

  defp handles(account, project), do: %{"account_handle" => account.name, "project_handle" => project.name}

  test "get_test_run_coverage gives the totals, targets, history and its commit's baseline", %{conn: conn, pr: pr} do
    result = call(GetTestRunCoverage, conn, %{"test_run_id" => pr.id})

    assert {result["coverage"], result["partial"], result["covered_lines"], result["executable_lines"]} ==
             {66.7, false, 4, 6}

    assert [%{"name" => "App", "files_count" => 2, "coverage" => 66.7}] = result["targets"]
    assert result["git_history"]["merge_base_sha"] == "b"
    assert result["git_history"]["history_source"] == "client"
    assert result["git_history"]["git_dirty"] == false
    assert result["baseline"]["commit"] == "b"
    assert result["baseline"]["depth"] == 0
    assert result["baseline_reason"] == nil
  end

  test "get_test_run_coverage explains a missing baseline and refuses a run without coverage", %{
    conn: conn,
    project: project,
    account: account
  } do
    orphan =
      CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1])], %{
        git_commit_sha: "zzz",
        git_branch: "feature",
        is_pull_request: true,
        pull_request_number: 6,
        base_branch: "main",
        merge_base_sha: "unknown"
      })

    result = call(GetTestRunCoverage, conn, %{"test_run_id" => orphan.id})
    assert result["baseline"] == nil
    assert result["baseline_reason"]["kind"] == "no_history"
    assert result["baseline_reason"]["message"] =~ "unknown"

    {:ok, bare} =
      Tuist.Tests.create_test(%{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1,
        status: "success",
        scheme: "App",
        git_branch: "main",
        git_commit_sha: "q",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: []
      })

    assert %{"isError" => true, "content" => [%{"text" => text}]} =
             GetTestRunCoverage.call(conn, %{"test_run_id" => bare.id})

    assert text =~ "gathered no coverage"
  end

  test "list_test_run_coverage_files pages the files least covered first", %{conn: conn, pr: pr} do
    result = call(ListTestRunCoverageFiles, conn, %{"test_run_id" => pr.id, "page_size" => 1})

    assert [%{"path" => "Sources/A.swift", "coverage" => 50.0, "targets" => ["App"]}] = result["files"]
    assert result["pagination_metadata"]["total_count"] == 2
    assert result["pagination_metadata"]["has_next_page"] == true

    result = call(ListTestRunCoverageFiles, conn, %{"test_run_id" => pr.id, "page" => 2, "page_size" => 1})
    assert [%{"path" => "Sources/B.swift"}] = result["files"]
  end

  test "get_test_run_coverage_file gives the lines, uncovered ranges and functions", %{conn: conn, pr: pr} do
    result = call(GetTestRunCoverageFile, conn, %{"test_run_id" => pr.id, "path" => "Sources/A.swift"})

    assert result["lines"] == [[1, 1], [2, 1], [3, 0], [4, 0]]
    assert result["uncovered_ranges"] == [[3, 4]]
    assert result["functions"] == []

    assert %{"isError" => true} = GetTestRunCoverageFile.call(conn, %{"test_run_id" => pr.id, "path" => "Missing.swift"})
  end

  test "get_test_run_coverage_comparison compares the run's commit with its baseline", %{conn: conn, pr: pr} do
    result = call(GetTestRunCoverageComparison, conn, %{"test_run_id" => pr.id})

    assert result["commit"]["sha"] == "p"
    assert result["total_delta"] == -33.3
    assert result["baseline"]["commit"] == "b"
    assert [%{"scheme" => "App", "coverage" => 66.7, "baseline_coverage" => 100.0, "delta" => -33.3}] = result["schemes"]
    assert [%{"name" => "App", "delta" => -33.3}] = result["targets"]

    assert [%{"path" => "Sources/A.swift", "coverage" => 50.0, "baseline_coverage" => 100.0, "delta" => -50.0}] =
             result["files"]

    assert result["patch"]["status"] == "available"

    assert {result["patch"]["covered_lines"], result["patch"]["executable_lines"], result["patch"]["coverage"]} ==
             {0, 2, 0.0}

    assert [%{"path" => "Sources/A.swift", "uncovered_ranges" => [[3, 4]]}] = result["patch"]["files"]
    assert result["gaps"] == [%{"path" => "Sources/A.swift", "executable_lines" => 2}]
  end

  test "get_commit_coverage and get_commit_coverage_comparison describe a commit", %{
    conn: conn,
    account: account,
    project: project,
    pr: pr
  } do
    result = call(GetCommitCoverage, conn, Map.put(handles(account, project), "git_commit_sha", "p"))

    assert {result["coverage"], result["schemes"], result["partial_schemes"], result["complete"]} ==
             {66.7, ["App"], [], false}

    assert result["test_run_ids"] == [pr.id]
    assert {result["measured_files_count"], result["unmeasured_files_count"]} == {2, 0}
    refute Map.has_key?(result, "files_count")
    assert [%{"name" => "App"}] = result["targets"]
    assert result["baseline"]["commit"] == "b"

    result = call(GetCommitCoverageComparison, conn, Map.put(handles(account, project), "git_commit_sha", "p"))
    assert result["total_delta"] == -33.3

    assert %{"isError" => true} = GetCommitCoverage.call(conn, Map.put(handles(account, project), "git_commit_sha", "q"))
  end

  test "list_commit_coverage_files and get_commit_coverage_file read a commit's files", %{
    conn: conn,
    account: account,
    project: project
  } do
    result = call(ListCommitCoverageFiles, conn, Map.put(handles(account, project), "git_commit_sha", "p"))

    # Least covered first, and the union of the commit's runs.
    assert Enum.map(result["files"], &{&1["path"], &1["coverage"]}) == [
             {"Sources/A.swift", 50.0},
             {"Sources/B.swift", 100.0}
           ]

    assert result["pagination_metadata"]["total_count"] == 2

    result =
      call(
        GetCommitCoverageFile,
        conn,
        Map.merge(handles(account, project), %{"git_commit_sha" => "p", "path" => "Sources/A.swift"})
      )

    assert result["coverage"] == 50.0
    assert result["uncovered_ranges"] == [[3, 4]]

    assert %{"isError" => true} =
             GetCommitCoverageFile.call(
               conn,
               Map.merge(handles(account, project), %{"git_commit_sha" => "p", "path" => "Sources/Nothing.swift"})
             )
  end

  test "list_coverage_history lists a branch's commits, measured or not", %{
    conn: conn,
    account: account,
    project: project
  } do
    Tuist.GitHistory.record_branch_head(CoverageFixtures.repository_id(account), "feature", "p")

    result =
      call(ListCoverageHistory, conn, Map.merge(handles(account, project), %{"branch" => "feature", "days" => 3650}))

    assert result["ordered_by"] == "graph"

    assert Enum.map(result["commits"], &{&1["git_commit_sha"], &1["measured"], &1["chained"], &1["coverage"]}) == [
             {"p", true, true, 66.7},
             {"b", true, true, 100.0}
           ]
  end

  test "list_coverage_branches compares every branch's head with the default one", %{
    conn: conn,
    account: account,
    project: project
  } do
    CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1, 0])], %{
      git_branch: "other",
      git_commit_sha: "f",
      ran_at: NaiveDateTime.utc_now()
    })

    result = call(ListCoverageBranches, conn, Map.put(handles(account, project), "days", 3650))

    assert Enum.map(result["branches"], &{&1["git_branch"], &1["coverage"], &1["delta"]}) == [
             {"other", 50.0, -50.0},
             {"feature", 66.7, -33.3},
             {"main", 100.0, 0.0}
           ]
  end

  test "get_pull_request_coverage lists the pull request's commits and compares the newest", %{
    conn: conn,
    account: account,
    project: project,
    pr: pr
  } do
    result = call(GetPullRequestCoverage, conn, Map.put(handles(account, project), "pull_request_number", 5))

    assert result["pull_request_number"] == 5

    assert [%{"git_commit_sha" => "p", "schemes" => ["App"], "partial" => false, "test_run_ids" => [run_id]}] =
             result["commits"]

    assert run_id == pr.id
    assert result["comparison"]["commit"]["sha"] == "p"
    assert result["comparison"]["total_delta"] == -33.3

    assert %{"isError" => true} =
             GetPullRequestCoverage.call(conn, Map.put(handles(account, project), "pull_request_number", 99))
  end
end
