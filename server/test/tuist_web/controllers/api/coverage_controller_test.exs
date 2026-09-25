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

    test "answers 404 for a commit no run measured yet, and completes its first fold", %{
      conn: conn,
      prefix: prefix,
      user: user,
      project: project
    } do
      assert conn |> post("#{prefix}/commits/q/complete") |> json_response(:not_found)

      CoverageFixtures.run_with_coverage(project, user.account, [CoverageFixtures.file("Sources/A.swift", [1])], %{
        git_commit_sha: "q"
      })

      assert %{complete: true, completeness: "signal"} = Tuist.Tests.Coverage.Commits.summary(project.id, "q")
    end
  end
end
