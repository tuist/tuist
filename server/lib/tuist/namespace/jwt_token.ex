defmodule Tuist.Namespace.JWTToken do
  @moduledoc """
  Generates JWT tokens for Namespace authentication.
  """

  alias Tuist.Environment

  @doc """
  Generates an OpenID Connect ID token for Namespace authentication.

  The token includes:
  - iss: The issuer (current server URL from app_url)
  - sub: The Partner ID provided by Namespace
  - aud: "namespace.so" (required by Namespace)
  - iat: Issued at timestamp
  - exp: Expiration timestamp (5 minutes from now)
  """
  def generate_id_token do
    issuer = issuer()
    partner_id = Environment.namespace_partner_id()

    claims = %{
      "iss" => issuer,
      "sub" => partner_id,
      "aud" => "namespace.so",
      "iat" => DateTime.to_unix(DateTime.utc_now()),
      "exp" => DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.to_unix()
    }

    jwk = JOSE.JWK.from_pem(Environment.namespace_jwt_private_key())
    jws = %{"alg" => "RS256", "kid" => "namespace-jwt-key-1"}
    jwt = JOSE.JWT.from_map(claims)

    {_, token} = jwk |> JOSE.JWT.sign(jws, jwt) |> JOSE.JWS.compact()

    {:ok, token}
  end

  @doc """
  Gets the issuer URL using the configured app URL.
  """
  def issuer do
    String.trim_trailing(Environment.app_url(), "/")
  end

  @doc """
  Returns the list of trusted issuers for Namespace.
  """
  def trusted_issuers do
    [
      "https://tuist.dev",
      "https://staging.tuist.dev",
      "https://canary.tuist.dev"
    ]
  end

  @doc """
  Returns the public key in JWK format for the JWKS endpoint.
  """
  def public_jwk do
    private_jwk = JOSE.JWK.from_pem(Environment.namespace_jwt_private_key())

    public_jwk = JOSE.JWK.to_public(private_jwk)
    {_, public_jwk_map} = JOSE.JWK.to_map(public_jwk)

    public_jwk_map
    |> Map.put("use", "sig")
    |> Map.put("alg", "RS256")
    |> Map.put("kid", "namespace-jwt-key-1")
  end
end
