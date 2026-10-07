defmodule TuistOps.GitHub.OrgMembershipTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistOps.Environment
  alias TuistOps.GitHub.AppToken
  alias TuistOps.GitHub.OrgMembership

  setup :verify_on_exit!

  setup do
    stub(Environment, :github_repository, fn -> "tuist/tuist" end)
    stub(AppToken, :token, fn -> {:ok, "installation-token"} end)
    :ok
  end

  test "membership/1 reads the org from the repository owner" do
    expect(Req, :get, fn "https://api.github.com/orgs/tuist/memberships/octocat", opts ->
      assert {"Authorization", "Bearer installation-token"} in opts[:headers]
      {:ok, %Req.Response{status: 200, body: %{"state" => "active", "role" => "member"}}}
    end)

    assert {:ok, %{state: "active", role: "member"}} = OrgMembership.membership("octocat")
  end

  test "membership/1 maps 404 to :not_member" do
    stub(Req, :get, fn _url, _opts -> {:ok, %Req.Response{status: 404, body: %{}}} end)

    assert {:error, :not_member} = OrgMembership.membership("octocat")
  end

  test "set_role/2 PUTs the role" do
    expect(Req, :put, fn "https://api.github.com/orgs/tuist/memberships/octocat", opts ->
      assert JSON.decode!(opts[:body]) == %{"role" => "admin"}
      {:ok, %Req.Response{status: 200, body: %{"state" => "active", "role" => "admin"}}}
    end)

    assert {:ok, %{role: "admin"}} = OrgMembership.set_role("octocat", "admin")
  end

  test "surfaces GitHub errors" do
    stub(Req, :put, fn _url, _opts ->
      {:ok, %Req.Response{status: 403, body: %{"message" => "Resource not accessible"}}}
    end)

    assert {:error, {:github_status, 403, _}} = OrgMembership.set_role("octocat", "admin")
  end

  test "surfaces token failures without calling GitHub" do
    stub(AppToken, :token, fn -> {:error, {:missing_env, "GITHUB_APP_ID"}} end)
    reject(&Req.get/2)

    assert {:error, {:github_app_token, _}} = OrgMembership.membership("octocat")
  end
end
