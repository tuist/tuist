defmodule Atlas.Guardian.SecretFetcher do
  @moduledoc """
  Lets `Atlas.Guardian` change its signing key without invalidating the tokens
  it already issued.

  Tokens are signed with the configured `:secret_key`
  (`GUARDIAN_SECRET_KEY`) and carry a `kid` derived from it. A token is
  verified with the key its `kid` names: that key, or the verify-only
  `:previous_secret_key` (`GUARDIAN_SECRET_KEY_PREVIOUS`). A token without
  a `kid` was signed before keys had ids, so with the key that was current
  then: the previous key while one is set, otherwise the current one.

  To rotate: set the previous key to the current value and deploy (nothing
  changes), then set the current key to a new value right before a deploy.
  Changing the current key before the previous one is in place leaves pods
  that start in between rejecting every live token, and during the rolling
  restart tokens a new pod issues fail on old pods until they restart. Unset
  the previous key once every token signed with it has expired. Access tokens live a day (`Atlas.OAuth.TokenGenerator`);
  refresh tokens are Boruta's opaque tokens, which no key signs.
  """

  @behaviour Guardian.Token.Jwt.SecretFetcher

  use Guardian.Token.Jwt.SecretFetcher

  @impl true
  def fetch_signing_secret(mod, _opts) do
    case mod.config(:secret_key) do
      key when is_binary(key) -> if present?(key), do: {:ok, jwk(key)}, else: {:error, :secret_not_found}
      _ -> {:error, :secret_not_found}
    end
  end

  @impl true
  def fetch_verifying_secret(mod, headers, _opts) do
    keys = Enum.filter([mod.config(:secret_key), mod.config(:previous_secret_key)], &(is_binary(&1) and present?(&1)))

    key =
      case headers do
        %{"kid" => kid} -> Enum.find(keys, &(kid(&1) == kid))
        _ -> List.last(keys)
      end

    if key, do: {:ok, jwk(key)}, else: {:error, :secret_not_found}
  end

  @doc """
  The key id a token signed with `key` carries. A truncated hash, so it names
  the key without revealing it.
  """
  def kid(key), do: :sha256 |> :crypto.hash(key) |> binary_part(0, 12) |> Base.url_encode64(padding: false)

  # A blank key is unset, not a key: a whitespace-only previous key would
  # otherwise verify tokens with a value anyone can guess.
  defp present?(key), do: String.trim(key) != ""

  # Guardian copies a JWK's `kid` into the header of the tokens it signs.
  defp jwk(key), do: key |> JOSE.JWK.from_oct() |> Map.update!(:fields, &Map.put(&1, "kid", kid(key)))
end
