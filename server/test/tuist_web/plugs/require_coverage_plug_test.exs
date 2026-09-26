defmodule TuistWeb.Plugs.RequireCoveragePlugTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    base = "/api/projects/#{user.account.name}/#{project.name}"
    %{conn: Authentication.put_current_user(conn, user), base: base}
  end

  test "the coverage and Git history endpoints do not exist while the flag is off", %{conn: conn, base: base} do
    stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)

    for path <- ["/tests/coverage/settings", "/tests/git-history/settings"] do
      assert %{"message" => "Code coverage is in early access and is not enabled for this account."} =
               conn |> get(base <> path) |> json_response(404)
    end

    assert %{"message" => "Code coverage is in early access and is not enabled for this account."} =
             conn |> post(base <> "/tests/coverage/commits/abc/complete") |> json_response(404)
  end

  test "lets requests through once the account has the flag", %{conn: conn, base: base} do
    stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> true end)

    assert %{"inline_threshold_bytes" => _} = conn |> get(base <> "/tests/coverage/settings") |> json_response(200)
  end
end
