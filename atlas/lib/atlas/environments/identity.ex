defmodule Atlas.Environments.Identity do
  @moduledoc "Short-lived, audience-bound workload tokens. Never sent to a model or native client."

  def config, do: Application.get_env(:atlas, :environment_identity, [])

  def issuer, do: AtlasWeb.Endpoint.url()

  def public_keys do
    with {:ok, key, kid} <- signing_key() do
      {_, public} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
      {:ok, %{"keys" => [Map.merge(public, %{"kid" => kid, "alg" => "RS256", "use" => "sig"})]}}
    end
  end

  def token(identity, account_handle, audience) do
    with {:ok, key, kid} <- signing_key(),
         %URI{scheme: "https", host: host} when is_binary(host) <- URI.parse(__MODULE__.issuer()) do
      now = System.system_time(:second)

      claims = %{
        "iss" => __MODULE__.issuer(),
        "sub" => "user:" <> identity.owner_id,
        "aud" => audience,
        "iat" => now,
        "nbf" => now,
        "exp" => now + 300,
        "jti" => Ecto.UUID.generate(),
        "purpose" => "atlas-environment",
        "account_handle" => account_handle,
        "environment_id" => identity.environment_id
      }

      {_, token} = key |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => kid}, claims) |> JOSE.JWS.compact()
      {:ok, token}
    else
      _ -> {:error, :environment_identity_unavailable}
    end
  end

  defp signing_key do
    with pem when is_binary(pem) <- __MODULE__.config()[:private_key],
         key = JOSE.JWK.from_pem(pem),
         {_, %{"kty" => "RSA", "d" => _, "n" => modulus}} <- JOSE.JWK.to_map(key),
         {:ok, modulus} <- Base.url_decode64(modulus, padding: false),
         true <- byte_size(modulus) >= 256 do
      kid = JOSE.JWK.thumbprint(key)
      {:ok, key, kid}
    else
      _ -> {:error, :environment_identity_unavailable}
    end
  rescue
    _ -> {:error, :environment_identity_unavailable}
  end
end
