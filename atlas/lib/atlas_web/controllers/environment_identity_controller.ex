defmodule AtlasWeb.EnvironmentIdentityController do
  use AtlasWeb, :controller

  alias Atlas.Environments.Identity

  def discovery(conn, _params) do
    json(conn, %{
      issuer: Identity.issuer(),
      jwks_uri: Identity.issuer() <> "/.well-known/jwks.json",
      id_token_signing_alg_values_supported: ["RS256"],
      subject_types_supported: ["public"],
      response_types_supported: []
    })
  end

  def jwks(conn, _params) do
    case Identity.public_keys() do
      {:ok, keys} -> conn |> put_resp_header("cache-control", "public, max-age=300") |> json(keys)
      _ -> conn |> put_status(:service_unavailable) |> json(%{error: "identity_unavailable"})
    end
  end
end
