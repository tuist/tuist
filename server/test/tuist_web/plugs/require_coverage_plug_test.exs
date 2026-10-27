defmodule TuistWeb.Plugs.RequireCoveragePlugTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  @remote "https://github.com/acme/app"
  @sha String.duplicate("a", 40)

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    base = "/api/projects/#{user.account.name}/#{project.name}"
    %{conn: Authentication.put_current_user(conn, user), base: base}
  end

  test "the coverage endpoints and commit listings do not exist while the flag is off", %{conn: conn, base: base} do
    stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)

    assert %{"message" => "Code coverage is in early access and is not enabled for this account."} =
             conn |> get(base <> "/tests/coverage/settings") |> json_response(404)

    assert %{"message" => "Code coverage is in early access and is not enabled for this account."} =
             conn
             |> put_req_header("content-type", "application/json")
             |> post(base <> "/tests/git-history/listings/missing", %{repository_url: @remote, shas: [@sha]})
             |> json_response(404)

    assert %{"message" => "Code coverage is in early access and is not enabled for this account."} =
             conn |> post(base <> "/tests/coverage/commits/abc/complete") |> json_response(404)

    for path <- [
          "/tests/coverage",
          "/tests/coverage?branch=main",
          "/tests/coverage/commits/abc",
          "/tests/coverage/commits/abc/files",
          "/tests/coverage/commits/abc/file?path=Sources/A.swift"
        ] do
      assert %{"message" => "Code coverage is in early access and is not enabled for this account."} =
               conn |> get(base <> path) |> json_response(404)
    end
  end

  test "the commit graph is collected whether or not the flag is on", %{conn: conn, base: base} do
    stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)

    assert %{"window_days" => _} = conn |> get(base <> "/tests/git-history/settings") |> json_response(200)

    assert conn
           |> put_req_header("content-type", "application/json")
           |> post(base <> "/tests/git-history/commits/missing", %{repository_url: @remote, shas: [@sha]})
           |> json_response(200) == %{"missing" => [@sha]}
  end

  test "lets requests through once the account has the flag", %{conn: conn, base: base} do
    stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> true end)

    assert %{"inline_threshold_bytes" => _} = conn |> get(base <> "/tests/coverage/settings") |> json_response(200)
  end
end
