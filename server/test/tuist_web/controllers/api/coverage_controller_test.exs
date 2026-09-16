defmodule TuistWeb.API.CoverageControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
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
end
