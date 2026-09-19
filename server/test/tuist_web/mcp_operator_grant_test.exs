defmodule TuistWeb.MCPOperatorGrantTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Plug.Conn

  alias Tuist.Authentication
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  # Drives `/mcp` through the router with a real OAuth access token, which is
  # the shape every Atlas request and every direct OAuth client arrives in:
  # authentication assigns an `AuthenticatedAccount` to `current_subject` and
  # never populates `current_user`. Asserting the plug in isolation missed that
  # once already.

  setup :set_mimic_from_context

  setup do
    jwk = JOSE.JWK.generate_key({:okp, :Ed25519})
    pub_pem = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem() |> unwrap()

    stub(Tuist.Environment, :operator_grant_public_key, fn -> pub_pem end)
    stub(Tuist.Environment, :operator_grant_audience, fn -> "tuist-server" end)
    stub(Tuist.Environment, :operator_grant_max_ttl_seconds, fn -> 3600 end)
    stub(Tuist.Environment, :tuist_hosted?, fn -> false end)

    project = ProjectsFixtures.project_fixture(preload: [:account])

    operator =
      AccountsFixtures.user_fixture(
        email: "operator-#{System.unique_integer([:positive])}@tuist.dev",
        preload: [:account]
      )

    AccountsFixtures.oauth2_identity_fixture(user: operator, provider: :google)

    {:ok, signer: jwk, project: project, operator: operator}
  end

  # Mirrors the claims `Tuist.OAuth.TokenGenerator` mints for an OAuth grant:
  # the subject is the account, and the human is carried in `user_id`.
  defp oauth_token(operator) do
    {:ok, token, _claims} =
      Authentication.encode_and_sign(
        operator.account,
        %{
          "type" => "account",
          "scopes" => ["mcp"],
          "all_projects" => true,
          "user_id" => operator.id
        },
        token_type: :access,
        ttl: {1, :hour}
      )

    token
  end

  defp mcp_request(conn, token, headers) do
    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")

    conn =
      Enum.reduce(headers, conn, fn {name, value}, acc -> put_req_header(acc, name, value) end)

    post(conn, "/mcp", %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})
  end

  test "accepts a grant presented alongside an OAuth access token", %{
    conn: conn,
    signer: signer,
    project: project,
    operator: operator
  } do
    grant = mint(signer, claims(project.account.name, operator.email))

    conn = mcp_request(conn, oauth_token(operator), [{"x-tuist-operator-grant", grant}])

    refute conn.status == 401
  end

  test "rejects a grant minted for a different operator", %{
    conn: conn,
    signer: signer,
    project: project,
    operator: operator
  } do
    grant = mint(signer, claims(project.account.name, "someone-else@tuist.dev"))

    conn = mcp_request(conn, oauth_token(operator), [{"x-tuist-operator-grant", grant}])

    assert conn.status == 401
    assert JSON.decode!(conn.resp_body)["error"] == "operator_grant_rejected"
  end

  test "leaves a request with no grant header alone", %{conn: conn, operator: operator} do
    conn = mcp_request(conn, oauth_token(operator), [])

    refute conn.status == 401
  end

  defp claims(account_handle, sub) do
    now = System.system_time(:second)

    %{
      "iss" => "ops.tuist.dev",
      "aud" => "tuist-server",
      "sub" => sub,
      "account_handle" => account_handle,
      "tier" => "read",
      "reason" => "investigating",
      "jti" => "1",
      "iat" => now,
      "exp" => now + 600
    }
  end

  defp mint(signer, claims) do
    {_meta, token} = signer |> JOSE.JWT.sign(%{"alg" => "EdDSA"}, claims) |> JOSE.JWS.compact()
    token
  end

  defp unwrap({_kty, pem}), do: pem
  defp unwrap(pem) when is_binary(pem), do: pem
end
