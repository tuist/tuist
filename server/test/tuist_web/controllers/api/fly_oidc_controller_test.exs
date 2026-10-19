defmodule TuistWeb.API.FlyOIDCControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Guardian
  alias Tuist.KeyValueStore
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @identity %{
    issuer: "https://oidc.fly.io/example-org",
    organization_id: "123",
    application_id: "456"
  }

  setup do
    stub(KeyValueStore, :get_or_update, fn _, _, fetch -> fetch.() end)
    :ok
  end

  test "exchanges a signed Fly identity for only the explicitly trusted projects", %{conn: conn} do
    first = ProjectsFixtures.project_fixture(preload: [:account])
    second = ProjectsFixtures.project_fixture(account: first.account)
    ProjectsFixtures.project_fixture(account: first.account, vcs_connection: [repository_full_handle: "tuist/tuist"])

    for project <- [first, second] do
      {:ok, _} = Projects.create_fly_oidc_trust_policy(project, @identity)
    end

    token = signed_token()
    response = conn |> exchange(token) |> json_response(:ok)
    assert response["expires_in"] == 3600
    assert {:ok, claims} = Guardian.decode_and_verify(response["access_token"])
    assert Enum.sort(claims["project_ids"]) == Enum.sort([first.id, second.id])
    assert claims["scopes"] == ["ci"]
    assert claims["sub"] == to_string(first.account.id)
  end

  test "a repository claim in a Fly token cannot bypass workload trust", %{conn: conn} do
    ProjectsFixtures.project_fixture(vcs_connection: [repository_full_handle: "tuist/tuist"])

    response = conn |> exchange(signed_token(%{"repository" => "tuist/tuist"})) |> json_response(:unauthorized)
    assert response["message"] == "OIDC token signature verification failed"
    refute response["access_token"]
  end

  for {claim, value} <- [{"iss", "https://oidc.fly.io/other-org"}, {"org_id", "999"}, {"app_id", "999"}] do
    test "rejects an identity with a different #{claim}", %{conn: conn} do
      project = ProjectsFixtures.project_fixture()
      {:ok, _} = Projects.create_fly_oidc_trust_policy(project, @identity)

      response =
        conn
        |> exchange(signed_token(%{unquote(claim) => unquote(value)}))
        |> json_response(:unauthorized)

      refute response["access_token"]
    end
  end

  test "removing trust prevents subsequent exchanges", %{conn: conn} do
    project = ProjectsFixtures.project_fixture()
    {:ok, policy} = Projects.create_fly_oidc_trust_policy(project, @identity)
    token = signed_token()
    assert conn |> exchange(token) |> json_response(:ok)

    {:ok, _} = Projects.delete_fly_oidc_trust_policy(project, policy.id)
    assert conn |> exchange(token) |> json_response(:unauthorized)
  end

  test "another account cannot poison an explicitly targeted account's workload exchange", %{conn: conn} do
    victim = ProjectsFixtures.project_fixture(preload: [:account])
    attacker = ProjectsFixtures.project_fixture(preload: [:account])

    for project <- [victim, attacker] do
      {:ok, _} = Projects.create_fly_oidc_trust_policy(project, @identity)
    end

    response = conn |> exchange(signed_token(), String.upcase(victim.account.name)) |> json_response(:ok)
    assert {:ok, claims} = Guardian.decode_and_verify(response["access_token"])
    assert claims["project_ids"] == [victim.id]
    assert claims["sub"] == to_string(victim.account.id)
  end

  test "account selection cannot replace a trust policy", %{conn: conn} do
    trusted = ProjectsFixtures.project_fixture()
    untrusted = ProjectsFixtures.project_fixture(preload: [:account])
    {:ok, _} = Projects.create_fly_oidc_trust_policy(trusted, @identity)

    response = conn |> exchange(signed_token(), untrusted.account.name) |> json_response(:forbidden)
    refute response["access_token"]
  end

  test "refuses to choose between accounts trusting the same workload", %{conn: conn} do
    for _ <- 1..2 do
      project = ProjectsFixtures.project_fixture()
      {:ok, _} = Projects.create_fly_oidc_trust_policy(project, @identity)
    end

    response = conn |> exchange(signed_token()) |> json_response(:forbidden)
    assert response["message"] =~ "multiple Tuist accounts"
    refute response["access_token"]
  end

  for {claim, value} <- [{"aud", "other-service"}, {"exp", 0}, {"nbf", 99_999_999_999}] do
    test "rejects invalid #{claim} before issuing credentials", %{conn: conn} do
      project = ProjectsFixtures.project_fixture()
      {:ok, _} = Projects.create_fly_oidc_trust_policy(project, @identity)

      response =
        conn
        |> exchange(signed_token(%{unquote(claim) => unquote(value)}))
        |> json_response(:unauthorized)

      refute response["access_token"]
    end
  end

  defp exchange(conn, token, account_handle \\ nil) do
    body = if is_nil(account_handle), do: %{token: token}, else: %{token: token, account_handle: account_handle}

    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/api/auth/oidc/token", body)
  end

  defp signed_token(overrides \\ %{}) do
    key = JOSE.JWK.generate_key({:rsa, 2048})
    {_, public_key} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

    stub(Req, :get, fn _, _ ->
      {:ok, %{status: 200, body: %{"keys" => [Map.put(public_key, "kid", "fly-test-key")]}}}
    end)

    claims =
      Map.merge(
        %{
          "iss" => @identity.issuer,
          "org_id" => @identity.organization_id,
          "app_id" => @identity.application_id,
          "aud" => "tuist",
          "nbf" => 0,
          "exp" => DateTime.to_unix(DateTime.utc_now()) + 600,
          "sub" => "example-org:example-app:example-machine"
        },
        overrides
      )

    {_, token} = key |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "fly-test-key"}, claims) |> JOSE.JWS.compact()
    token
  end
end
