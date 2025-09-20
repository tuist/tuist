defmodule TuistWeb.WellKnownController do
  use TuistWeb, :controller

  alias Tuist.Environment
  alias Tuist.Namespace.JWTToken

  @doc """
  Returns the OpenID configuration for JWT verification.
  """
  def openid_configuration(conn, _params) do
    issuer = JWTToken.issuer()

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
    public_jwk = JWTToken.public_jwk()

    jwks = %{
      keys: [public_jwk]
    }

    conn
    |> put_resp_content_type("application/json")
    |> json(jwks)
  end

  @doc """
  Serves the Apple App Site Association file dynamically based on the environment.
  """
  def apple_app_site_association(conn, _params) do
    app_id = get_app_id()

    association = %{
      applinks: %{
        apps: [],
        details: [
          %{
            appID: app_id,
            paths: ["/*/*/previews/*"]
          }
        ]
      }
    }

    json(conn, association)
  end

  defp get_app_id do
    team_id = "U6LC622NKF"

    bundle_id =
      cond do
        Environment.stag?() -> "dev.tuist.app.staging"
        Environment.can?() -> "dev.tuist.app.canary"
        true -> "dev.tuist.app"
      end

    "#{team_id}.#{bundle_id}"
  end
end
