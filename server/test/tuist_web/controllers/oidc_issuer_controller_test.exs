defmodule TuistWeb.OIDCIssuerControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Sandboxes.Anthropic.Federation

  test "serves each account its own discovery document and the federation JWKS", %{conn: conn} do
    account = account_fixture()

    configuration =
      conn
      |> get("/oidc/accounts/#{account.id}/.well-known/openid-configuration")
      |> json_response(:ok)

    assert configuration["issuer"] == Federation.issuer(account.id)
    assert configuration["jwks_uri"] == Federation.issuer(account.id) <> "/jwks.json"

    jwks_path = URI.parse(configuration["jwks_uri"]).path
    assert conn |> get(jwks_path) |> json_response(:ok) == Federation.jwks()
  end

  test "answers 404 for an account that does not exist", %{conn: conn} do
    conn |> get("/oidc/accounts/0/.well-known/openid-configuration") |> json_response(:not_found)
    conn |> get("/oidc/accounts/not-an-id/jwks.json") |> json_response(:not_found)
  end
end
