defmodule Condukt.Secrets.Providers.Static do
  @moduledoc """
  Loads a plaintext value from trusted application configuration.

  Prefer a real secret manager for production. This provider is useful in
  tests, local notebooks, and places where the caller already fetched the
  secret through another trusted path.

      secrets: [
        API_TOKEN: {:static, token}
      ]
  """

  @behaviour Condukt.SecretProvider

  @impl Condukt.SecretProvider
  def load(opts) do
    case Keyword.fetch(opts, :value) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      {:ok, value} -> {:ok, to_string(value)}
      :error -> {:error, :static_secret_requires_value}
    end
  end
end
