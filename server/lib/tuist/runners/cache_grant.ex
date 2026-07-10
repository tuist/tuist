defmodule Tuist.Runners.CacheGrant do
  @moduledoc """
  Mints the per-account cache-signing grant delivered to runner jobs
  (spec #76).

  A grant is a compact EdDSA-signed token whose `scope` claim
  (`account-<id>`) the runner's Tuist EE CLI substitutes for the machine
  MAC when signing and validating cached artifacts — but only after
  verifying the grant OFFLINE against the public half baked into the
  binary. That makes a warm cache volume's binaries validate as local hits
  across VMs of the same account, while a raw environment-variable
  substitution (which any third-party fleet could set to an arbitrary
  consistent value) stays impossible: the cross-machine bar remains
  "extract the binary's obfuscated keys", not "set an env var".

  The signing key is distinct from the artifact-signing key and lives only
  server-side; verification is fully offline, so an unreachable server also
  degrades to the MAC default. When no signing key is configured `mint/1`
  returns nil: dispatch omits the grant, the CLI falls back to the MAC
  default, and the (unsigned) manifest + helper cache warmth still applies.
  """

  alias Tuist.Environment

  require Logger

  @issuer "tuist-runners"

  @doc """
  Mints a cache-signing grant for `account_id`, or nil when grant minting
  is disabled (no private key configured) or signing fails. Grants rotate
  per job while the scope they carry (`account-<id>`) is stable across
  jobs, so volume warmth persists.
  """
  def mint(account_id) when is_integer(account_id) do
    case private_jwk() do
      {:ok, jwk} ->
        now = System.system_time(:second)

        claims = %{
          "scope" => "account-#{account_id}",
          "aud" => Environment.cache_grant_audience(),
          "iss" => @issuer,
          "iat" => now,
          "exp" => now + Environment.cache_grant_ttl_seconds()
        }

        {_, token} =
          jwk
          |> JOSE.JWT.sign(%{"alg" => "EdDSA"}, claims)
          |> JOSE.JWS.compact()

        token

      :error ->
        nil
    end
  rescue
    e ->
      Logger.warning("runners: cache grant mint failed: #{Exception.message(e)}")
      nil
  end

  def mint(_), do: nil

  defp private_jwk do
    case Environment.cache_grant_private_key() do
      pem when is_binary(pem) and byte_size(pem) > 0 ->
        try do
          {:ok, JOSE.JWK.from_pem(pem)}
        rescue
          _ -> :error
        end

      _ ->
        :error
    end
  end
end
