defmodule TuistWeb.WellKnownController do
  use TuistWeb, :controller
  
  alias Tuist.Namespace.JWTToken
  
  @doc """
  Returns the OpenID configuration for JWT verification.
  """
  def openid_configuration(conn, _params) do
    issuer = JWTToken.get_issuer()
    
    configuration = %{
      issuer: issuer,
      jwks_uri: "#{issuer}/.well-known/jwks.json",
      response_types_supported: ["id_token"],
      subject_types_supported: ["public"],
      id_token_signing_alg_values_supported: ["RS256"],
      claims_supported: ["iss", "sub", "aud", "exp", "iat"],
      scopes_supported: ["openid"]
    }
    
    conn
    |> put_resp_content_type("application/json")
    |> json(configuration)
  end
  
  @doc """
  Returns the JSON Web Key Set (JWKS) for verifying JWT signatures.
  """
  def jwks(conn, _params) do
    # Get the public key in JWK format
    public_jwk = JWTToken.get_public_jwk()
    
    # Create the JWKS response with the public key
    jwks = %{
      keys: [public_jwk]
    }
    
    conn
    |> put_resp_content_type("application/json")
    |> json(jwks)
  end
end