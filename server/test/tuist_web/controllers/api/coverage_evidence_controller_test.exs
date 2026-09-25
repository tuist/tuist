defmodule TuistWeb.API.CoverageEvidenceControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    files = [CoverageFixtures.file("Sources/A.swift", [1, 0])]

    run =
      CoverageFixtures.run_with_coverage(project, user.account, files, %{
        recompute: false,
        coverage_evidence: %{
          paths: ["Sources/A.swift"],
          scopes: [
            %{kind: "test", module: "AppTests", suite: "ATests", name: "testA()", files: [0]},
            %{kind: "suite", module: "AppTests", suite: "ATests", name: "", files: [0]}
          ]
        }
      })

    bare = CoverageFixtures.run_with_coverage(project, user.account, files, %{recompute: false})
    base = "/api/projects/#{user.account.name}/#{project.name}/tests/coverage/runs"
    %{conn: Authentication.put_current_user(conn, user), base: base, run: run, bare: bare}
  end

  test "reports the run's evidence and its scopes", %{conn: conn, base: base, run: run} do
    response = conn |> get("#{base}/#{run.id}/evidence") |> json_response(200)

    assert %{"tests" => 1, "suites" => 1, "targets" => 0, "files" => 1} = response["summary"]
    assert [%{"kind" => "test", "scope_id" => "AppTests/ATests/testA()", "files_count" => 1}] = response["scopes"]
    assert %{"total_count" => 1, "current_page" => 1} = response["pagination_metadata"]

    assert %{"scopes" => [%{"kind" => "suite", "scope_id" => "AppTests/ATests"}]} =
             conn |> get("#{base}/#{run.id}/evidence", kind: "suite") |> json_response(200)
  end

  test "lists a test's files and a file's tests", %{conn: conn, base: base, run: run} do
    assert %{"files" => [%{"path" => "Sources/A.swift", "scope" => "test", "git_blob_id" => "blob-Sources/A.swift"}]} =
             conn
             |> get("#{base}/#{run.id}/evidence/files", module: "AppTests", suite: "ATests", name: "testA()")
             |> json_response(200)

    assert %{"tests" => [%{"name" => "testA()"}], "suites" => ["AppTests/ATests"], "targets" => []} =
             conn |> get("#{base}/#{run.id}/evidence/tests", path: "Sources/A.swift") |> json_response(200)
  end

  test "answers not found for a run without evidence", %{conn: conn, base: base, bare: bare} do
    assert %{"message" => "The test run gathered no coverage evidence"} =
             conn |> get("#{base}/#{bare.id}/evidence") |> json_response(404)
  end
end
