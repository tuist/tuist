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

  def assetlinks(conn, _params) do
    json(conn, [
      %{
        relation: ["delegate_permission/common.handle_all_urls"],
        target: %{
          namespace: "android_app",
          package_name: "dev.tuist.app",
          sha256_cert_fingerprints: android_cert_fingerprints()
        }
      }
    ])
  end

  defp android_cert_fingerprints do
    release = "D9:94:6C:7F:C9:CA:86:91:38:26:7C:21:BC:C9:92:10:91:DB:A7:31:C5:AE:8E:05:30:89:5B:11:94:CF:E2:2D"

    if Environment.prod?() do
      [release]
    else
      [
        release,
        # Debug signing certificate fingerprint used in development builds
        "FE:7D:E5:E6:63:5D:E6:2B:7F:20:C0:2A:E3:B4:1F:81:3A:26:1D:96:2F:E5:57:FF:A1:7F:E2:5B:CF:63:E4:77"
      ]
    end
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
