defmodule Tuist.MCP.Components.Tools.CoverageToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.MCP.Components.Tools.GetCoverage
  alias Tuist.MCP.Components.Tools.GetCoverageFile
  alias Tuist.MCP.Components.Tools.ListCoverageFiles
  alias Tuist.Tests.Coverage.Commits
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)

    CoverageFixtures.seed_history(
      user.account,
      [CoverageFixtures.commit("a", [], 0), CoverageFixtures.commit("b", ["a"], 1)],
      branch_heads: [{"main", "b"}]
    )

    CoverageFixtures.run_with_coverage(
      project,
      user.account,
      [
        CoverageFixtures.file("Sources/A.swift", [3, 1, 0, 0]),
        CoverageFixtures.file("Sources/Feature/B.swift", [1, 1], targets: ["Feature"])
      ],
      %{git_commit_sha: "a"}
    )

    Commits.signal_complete(project, "a")

    CoverageFixtures.run_with_coverage(project, user.account, [CoverageFixtures.file("Sources/A.swift", [1, 0, 0, 0])], %{
      git_commit_sha: "b"
    })

    %{
      conn: assign(conn, :current_subject, user),
      handles: %{"account_handle" => user.account.name, "project_handle" => project.name}
    }
  end

  defp structured(%{"structuredContent" => content}), do: content

  describe "get_coverage" do
    test "reads the default branch's latest complete commit", %{conn: conn, handles: handles} do
      assert %{"branch" => "main", "git_commit_sha" => "a", "complete" => true, "coverage" => 66.7} =
               conn |> GetCoverage.call(handles) |> structured()
    end

    test "reads a commit, which wins over a branch", %{conn: conn, handles: handles} do
      coverage =
        conn
        |> GetCoverage.call(Map.merge(handles, %{"git_commit_sha" => "b", "branch" => "main"}))
        |> structured()

      assert %{"git_commit_sha" => "b", "complete" => false} = coverage
      refute Map.has_key?(coverage, "branch")
    end

    test "says when nothing is found", %{conn: conn, handles: handles} do
      assert %{"isError" => true, "content" => [%{"text" => "No complete commit on branch other gathered coverage."}]} =
               GetCoverage.call(conn, Map.put(handles, "branch", "other"))

      assert %{"isError" => true, "content" => [%{"text" => "No run of commit c gathered coverage."}]} =
               GetCoverage.call(conn, Map.put(handles, "git_commit_sha", "c"))
    end

    test "is not available while the account does not have code coverage", %{conn: conn, handles: handles} do
      stub(Tuist.FeatureFlags, :coverage_enabled?, fn _account, _project -> false end)

      assert %{
               "isError" => true,
               "content" => [%{"text" => "Code coverage is in early access and is not enabled for this account."}]
             } = GetCoverage.call(conn, handles)
    end

    test "refuses someone without access to the project before saying anything else", %{handles: handles} do
      stub(Tuist.FeatureFlags, :coverage_enabled?, fn _account, _project -> false end)
      other = AccountsFixtures.user_fixture(preload: [:account])
      conn = %Plug.Conn{assigns: %{current_subject: other}}

      assert %{"isError" => true, "content" => [%{"text" => "You do not have access to project: " <> _}]} =
               GetCoverage.call(conn, handles)
    end
  end

  describe "list_coverage_files" do
    test "lists the files of a branch's latest complete commit or of a commit", %{conn: conn, handles: handles} do
      assert %{
               "git_commit_sha" => "a",
               "files" => [%{"path" => "Sources/A.swift", "coverage" => 50.0}],
               "pagination_metadata" => %{"total_count" => 2, "has_next_page" => true}
             } = conn |> ListCoverageFiles.call(Map.put(handles, "page_size", 1)) |> structured()

      assert %{"git_commit_sha" => "b", "files" => [%{"path" => "Sources/A.swift", "coverage" => 25.0}]} =
               conn
               |> ListCoverageFiles.call(Map.merge(handles, %{"git_commit_sha" => "b", "search" => "a.swift"}))
               |> structured()

      assert %{"files" => [%{"path" => "Sources/Feature/B.swift"}, %{"path" => "Sources/A.swift"}]} =
               conn
               |> ListCoverageFiles.call(Map.merge(handles, %{"sort_by" => "path", "sort_order" => "desc"}))
               |> structured()
    end
  end

  describe "get_coverage_file" do
    test "reads a file at a branch's latest complete commit, with its lines on request", %{conn: conn, handles: handles} do
      file = conn |> GetCoverageFile.call(Map.put(handles, "path", "Sources/A.swift")) |> structured()

      assert %{"git_commit_sha" => "a", "path" => "Sources/A.swift", "covered_lines" => 2, "executable_lines" => 4} =
               file

      refute Map.has_key?(file, "lines")

      assert %{"lines" => [%{"line" => 1, "count" => 3} | _]} =
               conn
               |> GetCoverageFile.call(Map.merge(handles, %{"path" => "Sources/A.swift", "include_lines" => true}))
               |> structured()
    end

    test "says when the commit holds no coverage of the file", %{conn: conn, handles: handles} do
      assert %{
               "isError" => true,
               "content" => [%{"text" => "No coverage of Sources/Missing.swift is kept for commit a." <> _}]
             } =
               GetCoverageFile.call(conn, Map.put(handles, "path", "Sources/Missing.swift"))
    end
  end
end
