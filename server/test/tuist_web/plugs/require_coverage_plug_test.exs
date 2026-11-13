defmodule TuistWeb.Plugs.RequireCoveragePlugTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  @remote "https://github.com/acme/app"
  @sha String.duplicate("a", 40)
  @message "Code coverage isn't available for this project's build system."

  setup %{conn: conn} do
    # Production, where coverage once needed an account flag.
    stub(Environment, :env, fn -> :prod end)
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :gradle)
    base = "/api/projects/#{user.account.name}/#{project.name}"
    %{conn: Authentication.put_current_user(conn, user), base: base, user: user}
  end

  test "the coverage endpoints and commit listings do not exist for a build system without coverage", %{
    conn: conn,
    base: base
  } do
    assert %{"message" => @message} = conn |> get(base <> "/tests/coverage/settings") |> json_response(404)

    assert %{"message" => @message} =
             conn
             |> put_req_header("content-type", "application/json")
             |> post(base <> "/tests/git-history/listings/missing", %{repository_url: @remote, shas: [@sha]})
             |> json_response(404)

    assert %{"message" => @message} = conn |> post(base <> "/tests/coverage/commits/abc/complete") |> json_response(404)

    for path <- [
          "/tests/coverage",
          "/tests/coverage?branch=main",
          "/tests/coverage/commits/abc",
          "/tests/coverage/commits/abc/files",
          "/tests/coverage/commits/abc/file?path=Sources/A.swift"
        ] do
      assert %{"message" => @message} = conn |> get(base <> path) |> json_response(404)
    end
  end

  test "the commit graph is collected for every build system", %{conn: conn, base: base} do
    assert %{"window_days" => _} = conn |> get(base <> "/tests/git-history/settings") |> json_response(200)

    assert conn
           |> put_req_header("content-type", "application/json")
           |> post(base <> "/tests/git-history/commits/missing", %{repository_url: @remote, shas: [@sha]})
           |> json_response(200) == %{"missing" => [@sha]}
  end

  test "lets requests for Xcode, Mix and Cargo projects through in every account", %{conn: conn, user: user} do
    for build_system <- [:xcode, :mix, :cargo] do
      project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: build_system)
      base = "/api/projects/#{user.account.name}/#{project.name}"

      assert %{"inline_threshold_bytes" => _} = conn |> get(base <> "/tests/coverage/settings") |> json_response(200)

      assert conn
             |> put_req_header("content-type", "application/json")
             |> post(base <> "/tests/git-history/listings/missing", %{repository_url: @remote, shas: [@sha]})
             |> json_response(200)
    end
  end
end
