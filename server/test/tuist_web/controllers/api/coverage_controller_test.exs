defmodule TuistWeb.API.CoverageControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import OpenApiSpex.TestAssertions, only: [assert_schema: 3]

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Environment
  alias Tuist.Storage
  alias Tuist.Tests.Coverage.Commits
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.API.Spec
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    conn = conn |> Authentication.put_current_user(user) |> put_req_header("content-type", "application/json")
    %{conn: conn, user: user, project: project}
  end

  test "settings return the inline threshold", %{conn: conn, user: user, project: project} do
    stub(Environment, :coverage_inline_threshold_bytes, fn -> 42 end)

    assert conn
           |> get("/api/projects/#{user.account.name}/#{project.name}/tests/coverage/settings")
           |> json_response(:ok) == %{"inline_threshold_bytes" => 42}
  end

  test "uploads return the run's key and a signed URL for it", %{conn: conn, user: user, project: project} do
    run_id = UUIDv7.generate()
    key = "#{user.account.name}/#{project.name}/runs/#{run_id}/coverage.ndjson.deflate"
    expect(Storage, :generate_upload_url, fn ^key, _account -> "https://storage/#{key}?signed" end)

    assert conn
           |> post("/api/projects/#{user.account.name}/#{project.name}/tests/coverage/uploads", %{test_run_id: run_id})
           |> json_response(:ok) == %{"storage_key" => key, "upload_url" => "https://storage/#{key}?signed"}
  end

  describe "completing a commit" do
    setup %{user: user, project: project} do
      CoverageFixtures.seed_history(user.account, [CoverageFixtures.commit("p", [], 0)])

      run =
        CoverageFixtures.run_with_coverage(
          project,
          user.account,
          [CoverageFixtures.file("Sources/A.swift", [1, 1, 0, 0]), CoverageFixtures.file("Sources/B.swift", [1, 1])],
          %{git_commit_sha: "p"}
        )

      %{run: run, prefix: "/api/projects/#{user.account.name}/#{project.name}/tests/coverage"}
    end

    test "republishes the commit's coverage as complete", %{conn: conn, prefix: prefix, run: run} do
      completed = conn |> post("#{prefix}/commits/p/complete") |> json_response(:ok)

      assert {completed["coverage"], completed["schemes"], completed["complete"], completed["completeness"]} ==
               {66.7, ["App"], true, "signal"}

      assert completed["test_run_ids"] == [run.id]
      assert [%{"name" => "App", "coverage" => 66.7}] = completed["targets"]
    end

    test "answers 202 for a commit no run measured yet, and completes its first fold", %{
      conn: conn,
      prefix: prefix,
      user: user,
      project: project
    } do
      assert conn |> post("#{prefix}/commits/q/complete") |> json_response(:accepted)

      CoverageFixtures.run_with_coverage(project, user.account, [CoverageFixtures.file("Sources/A.swift", [1])], %{
        git_commit_sha: "q"
      })

      assert %{complete: true, completeness: "signal"} = Commits.summary(project.id, "q")
    end
  end

  describe "reading coverage" do
    setup %{user: user, project: project} do
      CoverageFixtures.seed_history(
        user.account,
        [CoverageFixtures.commit("a", [], 0), CoverageFixtures.commit("b", ["a"], 1)],
        branch_heads: [{"main", "b"}]
      )

      functions = [
        %{name: "covered()", line_number: 1, execution_count: 3, covered_lines: 2, executable_lines: 2},
        %{name: "uncovered()", line_number: 3, execution_count: 0, covered_lines: 0, executable_lines: 2}
      ]

      CoverageFixtures.run_with_coverage(
        project,
        user.account,
        [
          "Sources/A.swift" |> CoverageFixtures.file([3, 1, 0, 0]) |> Map.put(:functions, functions),
          CoverageFixtures.file("Sources/Feature/B.swift", [1, 1], targets: ["Feature"])
        ],
        %{git_commit_sha: "a"}
      )

      Commits.signal_complete(project, "a")

      CoverageFixtures.run_with_coverage(
        project,
        user.account,
        [CoverageFixtures.file("Sources/A.swift", [1, 0, 0, 0])],
        %{
          git_commit_sha: "b"
        }
      )

      %{prefix: "/api/projects/#{user.account.name}/#{project.name}/tests/coverage"}
    end

    test "a branch reads as its latest complete commit, the default branch unless one is given", %{
      conn: conn,
      prefix: prefix
    } do
      coverage = conn |> get(prefix) |> json_response(:ok)

      assert_schema(coverage, "BranchCoverage", Spec.spec())
      assert %{"branch" => "main", "git_commit_sha" => "a", "complete" => true, "coverage" => 66.7} = coverage
      assert coverage["targets"] |> Enum.map(& &1["name"]) |> Enum.sort() == ["App", "Feature"]

      assert %{"git_commit_sha" => "a"} = conn |> get(prefix <> "?branch=main") |> json_response(:ok)
    end

    test "a branch without a complete commit is not found", %{conn: conn, prefix: prefix} do
      assert %{"message" => "No complete commit on branch feature/x gathered coverage."} =
               conn |> get(prefix <> "?branch=feature/x") |> json_response(:not_found)
    end

    test "a commit reads as its coverage, complete or not", %{conn: conn, prefix: prefix} do
      coverage = conn |> get(prefix <> "/commits/b") |> json_response(:ok)

      assert_schema(coverage, "CommitCoverage", Spec.spec())

      assert %{"git_commit_sha" => "b", "complete" => false, "coverage" => 25.0, "targets" => [%{"name" => "App"}]} =
               coverage

      assert %{"message" => "No run of commit c gathered coverage."} =
               conn |> get(prefix <> "/commits/c") |> json_response(:not_found)
    end

    test "a commit's files are listed a page at a time", %{conn: conn, prefix: prefix} do
      page = conn |> get(prefix <> "/commits/a/files?page_size=1") |> json_response(:ok)

      assert_schema(page, "CommitCoverageFiles", Spec.spec())

      assert %{
               "git_commit_sha" => "a",
               "files" => [
                 %{"path" => "Sources/A.swift", "covered_lines" => 2, "executable_lines" => 4, "coverage" => 50.0}
               ],
               "pagination_metadata" => %{
                 "current_page" => 1,
                 "page_size" => 1,
                 "total_count" => 2,
                 "total_pages" => 2,
                 "has_next_page" => true,
                 "has_previous_page" => false
               }
             } = page

      assert %{
               "files" => [%{"path" => "Sources/Feature/B.swift"}],
               "pagination_metadata" => %{"has_previous_page" => true}
             } =
               conn |> get(prefix <> "/commits/a/files?page_size=1&page=2") |> json_response(:ok)

      assert %{"files" => [%{"path" => "Sources/Feature/B.swift"}, %{"path" => "Sources/A.swift"}]} =
               conn |> get(prefix <> "/commits/a/files?sort_by=path&sort_order=desc") |> json_response(:ok)

      assert %{"files" => [%{"path" => "Sources/Feature/B.swift"}], "pagination_metadata" => %{"total_count" => 1}} =
               conn |> get(prefix <> "/commits/a/files?search=feature") |> json_response(:ok)

      assert conn |> get(prefix <> "/commits/a/files?page_size=101") |> json_response(:bad_request)
      assert conn |> get(prefix <> "/commits/c/files") |> json_response(:not_found)
    end

    test "a file reads with its functions, and its lines on request", %{conn: conn, prefix: prefix} do
      file = conn |> get(prefix <> "/commits/a/file?path=Sources/A.swift") |> json_response(:ok)

      assert %{
               "git_commit_sha" => "a",
               "path" => "Sources/A.swift",
               "git_blob_id" => "blob-Sources/A.swift",
               "targets" => ["App"],
               "covered_lines" => 2,
               "executable_lines" => 4,
               "coverage" => 50.0,
               "carried_lines" => [],
               "functions" => [
                 %{"name" => "covered()", "line_number" => 1, "execution_count" => 3, "covered_lines" => 2},
                 %{"name" => "uncovered()", "line_number" => 3, "covered_lines" => 0, "executable_lines" => 2}
               ]
             } = file

      assert_schema(file, "CoverageFileDetail", Spec.spec())
      refute Map.has_key?(file, "lines")
      refute file["functions"] |> hd() |> Map.has_key?("confirmed_lines")

      with_lines =
        conn |> get(prefix <> "/commits/a/file?path=Sources/A.swift&include_lines=true") |> json_response(:ok)

      assert_schema(with_lines, "CoverageFileDetail", Spec.spec())

      assert %{"lines" => [%{"line" => 1, "count" => 3}, %{"line" => 2, "count" => 1}, %{"line" => 3, "count" => 0}, _]} =
               with_lines
    end

    test "a file the commit holds no coverage of is not found", %{conn: conn, prefix: prefix} do
      assert %{"message" => "No coverage of Sources/Missing.swift is kept for commit a." <> _} =
               conn |> get(prefix <> "/commits/a/file?path=Sources/Missing.swift") |> json_response(:not_found)

      assert %{"message" => "No run of commit c gathered coverage."} =
               conn |> get(prefix <> "/commits/c/file?path=Sources/A.swift") |> json_response(:not_found)

      assert conn |> get(prefix <> "/commits/a/file") |> json_response(:bad_request)
    end

    test "an account token that reads the project's tests reads its coverage", %{
      conn: conn,
      prefix: prefix,
      user: user
    } do
      conn =
        assign(conn, :current_subject, %AuthenticatedAccount{
          account: user.account,
          scopes: ["project:tests:read"],
          all_projects: true
        })

      assert %{"git_commit_sha" => "a"} = conn |> get(prefix <> "/commits/a") |> json_response(:ok)
    end

    test "someone without access to the project reads nothing", %{conn: conn, project: project, user: user} do
      other = AccountsFixtures.user_fixture(preload: [:account])

      assert conn
             |> Authentication.put_current_user(other)
             |> get("/api/projects/#{user.account.name}/#{project.name}/tests/coverage/commits/a")
             |> json_response(:forbidden)
    end
  end
end
