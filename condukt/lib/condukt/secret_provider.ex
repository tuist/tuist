defmodule Condukt.SecretProvider do
  @moduledoc """
  Behaviour for loading session secrets from trusted providers.

  Secret providers run in trusted application code while a session starts.
  They return plaintext values to Condukt, which keeps them out of the model
  context and exposes them to tools as environment variables.

  Providers receive the keyword options from a single secret source:

      defmodule MyApp.Secrets.Vault do
        @behaviour Condukt.SecretProvider

        @impl true
        def load(opts) do
          MyApp.Vault.read(Keyword.fetch!(opts, :path))
        end
      end

      MyAgent.start_link(
        secrets: [
          DATABASE_URL: {MyApp.Secrets.Vault, path: "apps/dev/database_url"}
        ]
      )
  """

  @doc """
  Loads one secret value from the provider-specific options.
  """
  @callback load(opts :: keyword()) :: {:ok, String.t()} | {:error, term()}
end
