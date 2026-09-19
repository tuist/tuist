defmodule TuistWeb.API.CoverageControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
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

  describe "reading coverage" do
    setup %{user: user, project: project} do
      CoverageFixtures.seed_history(user.account, [
        CoverageFixtures.commit("b", [], 0),
        CoverageFixtures.commit("p", ["b"], 1)
      ])

      base =
        CoverageFixtures.run_with_coverage(
          project,
          user.account,
          [CoverageFixtures.file("Sources/A.swift", [1, 1, 1, 1]), CoverageFixtures.file("Sources/B.swift", [1, 1])],
          %{git_commit_sha: "b", ran_at: ~N[2026-09-01 00:30:00]}
        )

      pr =
        CoverageFixtures.run_with_coverage(
          project,
          user.account,
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

      %{base: base, pr: pr, prefix: "/api/projects/#{user.account.name}/#{project.name}/tests/coverage"}
    end

    test "a run's coverage, files, one file and its commit's comparison", %{conn: conn, prefix: prefix, pr: pr} do
      run = conn |> get("#{prefix}/runs/#{pr.id}") |> json_response(:ok)
      assert {run["coverage"], run["partial"]} == {66.7, false}
      assert [%{"name" => "App", "coverage" => 66.7}] = run["targets"]
      assert run["git_history"]["merge_base_sha"] == "b"
      assert run["git_history"]["git_dirty"] == false
      assert run["baseline"]["commit"] == "b"
      assert run["baseline"]["schemes"] == ["App"]

      files = conn |> get("#{prefix}/runs/#{pr.id}/files?page_size=1") |> json_response(:ok)
      assert [%{"path" => "Sources/A.swift", "coverage" => 50.0}] = files["files"]

      assert files["pagination_metadata"] == %{
               "current_page" => 1,
               "page_size" => 1,
               "total_count" => 2,
               "total_pages" => 2
             }

      file = conn |> get("#{prefix}/runs/#{pr.id}/file?path=Sources/A.swift") |> json_response(:ok)
      assert file["lines"] == [[1, 1], [2, 1], [3, 0], [4, 0]]
      assert file["uncovered_ranges"] == [[3, 4]]

      comparison = conn |> get("#{prefix}/runs/#{pr.id}/comparison") |> json_response(:ok)
      assert comparison["commit"]["sha"] == "p"
      assert comparison["total_delta"] == -33.3
      assert [%{"scheme" => "App", "delta" => -33.3}] = comparison["schemes"]
      assert comparison["patch"]["status"] == "available"
      assert comparison["gaps"] == [%{"path" => "Sources/A.swift", "executable_lines" => 2}]
    end

    test "a commit's coverage, files, one file, comparison and completion", %{conn: conn, prefix: prefix, pr: pr} do
      commit = conn |> get("#{prefix}/commits/p") |> json_response(:ok)
      assert {commit["coverage"], commit["schemes"], commit["complete"]} == {66.7, ["App"], false}
      assert commit["test_run_ids"] == [pr.id]
      assert [%{"name" => "App", "coverage" => 66.7}] = commit["targets"]
      assert commit["baseline"]["commit"] == "b"

      files = conn |> get("#{prefix}/commits/p/files?page_size=1") |> json_response(:ok)
      assert [%{"path" => "Sources/A.swift", "coverage" => 50.0}] = files["files"]
      assert files["pagination_metadata"]["total_count"] == 2

      file = conn |> get("#{prefix}/commits/p/file?path=Sources/A.swift") |> json_response(:ok)
      assert file["uncovered_ranges"] == [[3, 4]]

      comparison = conn |> get("#{prefix}/commits/p/comparison") |> json_response(:ok)
      assert comparison["total_delta"] == -33.3
      assert comparison["baseline"]["commit"] == "b"

      completed = conn |> post("#{prefix}/commits/p/complete") |> json_response(:ok)
      assert {completed["complete"], completed["completeness"]} == {true, "signal"}
      assert conn |> get("#{prefix}/commits/p") |> json_response(:ok) |> Map.get("complete") == true
    end

    test "history, branches and a pull request", %{conn: conn, prefix: prefix} do
      history = conn |> get("#{prefix}/history?branch=main&days=3650") |> json_response(:ok)
      assert history["ordered_by"] == "time"
      assert [%{"git_commit_sha" => "b", "measured" => true, "chained" => true, "coverage" => 100.0}] = history["commits"]

      branches = conn |> get("#{prefix}/branches?days=3650") |> json_response(:ok)

      assert [
               %{"git_branch" => "feature", "git_commit_sha" => "p", "delta" => -33.3, "ordered_by" => "time"},
               %{"git_branch" => "main", "delta" => +0.0}
             ] = branches["branches"]

      pull_request = conn |> get("#{prefix}/pull-requests/5") |> json_response(:ok)
      assert [%{"git_commit_sha" => "p", "schemes" => ["App"]}] = pull_request["commits"]
      assert pull_request["comparison"]["baseline"]["commit"] == "b"
    end

    test "answers 404 for a missing run, a run without coverage, a missing file, an unmeasured commit and a pull request without runs",
         %{
           conn: conn,
           prefix: prefix,
           pr: pr,
           user: user,
           project: project
         } do
      assert conn |> get("#{prefix}/runs/#{UUIDv7.generate()}") |> json_response(:not_found)

      {:ok, bare} =
        Tuist.Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: user.account.id,
          duration: 1,
          status: "success",
          scheme: "App",
          git_branch: "main",
          git_commit_sha: "q",
          ran_at: NaiveDateTime.utc_now(),
          is_ci: true,
          test_modules: []
        })

      assert conn |> get("#{prefix}/runs/#{bare.id}/comparison") |> json_response(:not_found)
      assert conn |> get("#{prefix}/runs/#{pr.id}/file?path=Missing.swift") |> json_response(:not_found)
      assert conn |> get("#{prefix}/commits/q") |> json_response(:not_found)
      assert conn |> post("#{prefix}/commits/q/complete") |> json_response(:not_found)
      assert conn |> get("#{prefix}/pull-requests/99") |> json_response(:not_found)
    end
  end
end
