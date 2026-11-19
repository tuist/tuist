defmodule Tuist.Sandboxes.AtlasIdentity do
  @moduledoc false

  alias Tuist.Accounts.OIDCTrustPolicy
  alias Tuist.OIDC.Workload

  def trusts, do: Application.get_env(:tuist, :atlas_environment_trust, %{})

  def verify(token, account_handle, environment_id) do
    with {:ok, ^environment_id} <- Ecto.UUID.cast(environment_id),
         %{"issuer" => issuer} = trust <- __MODULE__.trusts()[account_handle],
         policy = %OIDCTrustPolicy{
           issuer: issuer,
           jwks_url: issuer <> "/.well-known/jwks.json",
           audience: "tuist-environments",
           claims: %{
             "purpose" => "atlas-environment",
             "account_handle" => account_handle,
             "environment_id" => environment_id
           }
         },
         {:ok, claims} <- Workload.verify_identity(token, policy),
         "user:" <> owner_id <- claims["sub"],
         {:ok, ^owner_id} <- Ecto.UUID.cast(owner_id),
         true <- is_nil(trust["subjects"]) or claims["sub"] in trust["subjects"],
         issued when is_integer(issued) <- claims["iat"],
         true <- issued <= System.system_time(:second) + 60 and (claims["exp"] - issued) in 1..300 do
      key = :sha256 |> :crypto.hash(JSON.encode!([issuer, claims["sub"], environment_id])) |> Base.encode16(case: :lower)
      {:ok, key}
    else
      _ -> {:error, :unauthorized}
    end
  rescue
    _ -> {:error, :unauthorized}
  end
end
