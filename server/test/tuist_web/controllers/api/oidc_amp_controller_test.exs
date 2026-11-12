defmodule TuistWeb.API.OIDCAmpControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.OIDCTrustPolicy
  alias Tuist.Guardian
  alias Tuist.KeyValueStore
  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.OIDC.JWKSClient
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @issuer "https://ampcode.com/api/workload-identity"
  @workspace_id "8e5f0d8f-a1a5-429d-843d-6096a60fa0a1"
  @project_id "1e345004-78e8-4e1d-bb72-27bb1a22d450"

  setup_all do
    %{key: JOSE.JWK.generate_key({:rsa, 2048}), other_key: JOSE.JWK.generate_key({:rsa, 2048})}
  end

  setup %{key: key} do
    stub(KeyValueStore, :get_or_update, fn _, _, fetch -> fetch.() end)

    stub(Req, :get, fn "https://ampcode.com/api/workload-identity/jwks.json", _opts ->
      {:ok, %{status: 200, body: jwks(key)}}
    end)

    %{project: ProjectsFixtures.project_fixture(preload: [:account])}
  end

  test "issues account-wide CI and sandbox access to Orbs of a connected workspace", %{
    conn: conn,
    key: key,
    project: project
  } do
    {:ok, _} = Accounts.create_amp_workspace_connection(project.account, %{workspace_id: @workspace_id})

    response = conn |> exchange(sign(key)) |> json_response(:ok)

    assert {:ok, claims} = Guardian.decode_and_verify(response["access_token"])
    assert claims["sub"] == to_string(project.account.id)
    assert claims["scopes"] == ["ci", "account:sandboxes:write"]
    assert claims["all_projects"] == true

    assert %{"sandboxes" => []} =
             build_conn()
             |> put_req_header("authorization", "Bearer #{response["access_token"]}")
             |> get(~p"/api/accounts/#{project.account.name}/sandboxes")
             |> json_response(:ok)
  end

  test "rejects unconnected workspaces, personal threads, tokens not printed by amp orb id-token and other audiences", %{
    conn: conn,
    key: key,
    project: project
  } do
    {:ok, _} = Accounts.create_amp_workspace_connection(project.account, %{workspace_id: @workspace_id})

    assert %{"message" => "This Amp workspace or project is not connected" <> _} =
             conn
             |> exchange(sign(key, %{"workspace_id" => "5b3ca4b4-55a2-4d33-9c87-1d0b0f2f3c11"}))
             |> json_response(:forbidden)

    assert conn |> exchange(sign(key, %{"workspace_id" => nil})) |> json_response(:forbidden)
    assert conn |> exchange(sign(key, %{"token_use" => nil})) |> json_response(:forbidden)
    assert conn |> exchange(sign(key, %{"token_use" => "setup"})) |> json_response(:forbidden)
    assert conn |> exchange(sign(key, %{"aud" => "tuist"})) |> json_response(:unauthorized)
  end

  test "a project-scoped connection admits only Orbs of that Amp project", %{conn: conn, key: key, project: project} do
    {:ok, _} =
      Accounts.create_amp_workspace_connection(project.account, %{workspace_id: @workspace_id, project_id: @project_id})

    assert conn |> exchange(sign(key)) |> json_response(:ok)

    assert conn
           |> exchange(sign(key, %{"project_id" => "5b3ca4b4-55a2-4d33-9c87-1d0b0f2f3c11"}))
           |> json_response(:forbidden)

    assert conn |> exchange(sign(key, %{"project_id" => nil})) |> json_response(:forbidden)

    workspace_subject = %{"sub" => "workspace:#{@workspace_id}"}
    assert conn |> exchange(sign(key, workspace_subject)) |> json_response(:forbidden)
  end

  test "requires the subject to name the same workspace and project as the claims", %{
    conn: conn,
    key: key,
    project: project
  } do
    {:ok, _} = Accounts.create_amp_workspace_connection(project.account, %{workspace_id: @workspace_id})
    other_id = "5b3ca4b4-55a2-4d33-9c87-1d0b0f2f3c11"

    assert conn |> exchange(sign(key, %{"sub" => "workspace:#{@workspace_id}"})) |> json_response(:ok)

    assert conn
           |> exchange(sign(key, %{"sub" => "workspace:#{@workspace_id}:project:#{@project_id}"}))
           |> json_response(:ok)

    for subject <- [
          "workspace:#{other_id}:project:#{@project_id}:user:user_1:thread:T-1",
          "workspace:#{@workspace_id}:project:#{other_id}:user:user_1:thread:T-1",
          "workspace:#{@workspace_id}#{other_id}",
          "user:user_1:thread:T-1",
          nil
        ] do
      assert conn |> exchange(sign(key, %{"sub" => subject})) |> json_response(:forbidden)
    end
  end

  test "rejects tokens Amp did not sign", %{conn: conn, other_key: other_key, project: project} do
    {:ok, _} = Accounts.create_amp_workspace_connection(project.account, %{workspace_id: @workspace_id})

    assert conn |> exchange(sign(other_key)) |> json_response(:unauthorized)
  end

  test "requires an account handle when the workspace is connected to several accounts", %{
    conn: conn,
    key: key,
    project: project
  } do
    other = ProjectsFixtures.project_fixture(preload: [:account])
    {:ok, _} = Accounts.create_amp_workspace_connection(project.account, %{workspace_id: @workspace_id})
    {:ok, _} = Accounts.create_amp_workspace_connection(other.account, %{workspace_id: @workspace_id})

    assert %{"message" => message} = conn |> exchange(sign(key)) |> json_response(:forbidden)
    assert message =~ "TUIST_OIDC_ACCOUNT"
    assert message =~ project.account.name

    response = conn |> exchange(sign(key), other.account.name) |> json_response(:ok)
    assert {:ok, claims} = Guardian.decode_and_verify(response["access_token"])
    assert claims["sub"] == to_string(other.account.id)
  end

  test "an account handle cannot select an account the workspace is not connected to", %{
    conn: conn,
    key: key,
    project: project
  } do
    other = ProjectsFixtures.project_fixture(preload: [:account])
    {:ok, _} = Accounts.create_amp_workspace_connection(project.account, %{workspace_id: @workspace_id})

    assert conn |> exchange(sign(key), other.account.name) |> json_response(:forbidden)
  end

  test "falls back to the account's custom Amp trust policies", %{conn: conn, key: key, project: project} do
    stub(SSRFGuard, :pin, fn url -> {:ok, url, "ampcode.com"} end)
    stub(JWKSClient, :get, fn _url, _opts -> {:ok, %{status: 200, body: JSON.encode!(jwks(key))}} end)

    {:ok, _} =
      %OIDCTrustPolicy{account_id: project.account_id}
      |> OIDCTrustPolicy.changeset(%{
        name: "Amp",
        issuer: @issuer,
        jwks_url: "#{@issuer}/jwks.json",
        audience: "https://tuist.dev",
        claims: %{"user_id" => "user_1"}
      })
      |> Repo.insert()

    personal = sign(key, %{"workspace_id" => nil, "user_id" => "user_1"})

    assert conn |> exchange(personal) |> json_response(:forbidden)
    response = conn |> exchange(personal, project.account.name) |> json_response(:ok)
    assert {:ok, claims} = Guardian.decode_and_verify(response["access_token"])
    assert claims["sub"] == to_string(project.account.id)
    # Custom policies grant CI access only, like other workload policies.
    assert claims["scopes"] == ["ci"]

    build_conn()
    |> put_req_header("authorization", "Bearer #{response["access_token"]}")
    |> get(~p"/api/accounts/#{project.account.name}/sandboxes")
    |> json_response(:forbidden)
  end

  defp exchange(conn, token, account_handle \\ nil) do
    body = if account_handle, do: %{token: token, account_handle: account_handle}, else: %{token: token}

    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/api/auth/oidc/token", body)
  end

  defp sign(key, overrides \\ %{}) do
    claims =
      %{
        "iss" => @issuer,
        "aud" => "https://tuist.dev",
        "sub" => "workspace:#{@workspace_id}:project:#{@project_id}:user:user_1:thread:T-1",
        "exp" => DateTime.to_unix(DateTime.utc_now()) + 600,
        "workspace_id" => @workspace_id,
        "project_id" => @project_id,
        "user_id" => "user_1",
        "token_use" => "exchanged"
      }
      |> Map.merge(overrides)
      |> Map.reject(fn {_, value} -> is_nil(value) end)

    {_, token} = key |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "amp-key"}, claims) |> JOSE.JWS.compact()
    token
  end

  defp jwks(key) do
    {_, public} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    %{"keys" => [Map.merge(public, %{"kid" => "amp-key", "use" => "sig", "alg" => "RS256"})]}
  end
end
