defmodule Tuist.Runners.CacheToken do
  @moduledoc """
  Mints the tenant cache token handed to a runner at dispatch.

  The token authorizes a job's interactions with the self-hosted GitHub
  Actions cache gateway. It is asymmetrically signed (EdDSA/Ed25519): the
  server holds the private key and signs; the Go cache gateway holds only
  the public key and verifies, so the data plane carries no signing
  material. The token is short-lived and scoped to a single
  `{account, repo, fleet}` plus the GitHub ref-scope dimensions, so a
  valid token for one tenant can never address another tenant's cache,
  and a job can only read cache from its own ref, its PR base ref, and
  the default branch (untrusted forks are isolated to their own ref).

  The host-side proxy stages this token per guest and injects it as the
  bearer to the gateway; the guest never holds the secret.
  """

  alias Tuist.Environment

  # Short lifetime: a token only needs to cover one job's cache traffic.
  @ttl_seconds 600

  @doc """
  Whether the self-hosted cache is enabled (a signing key is configured).
  """
  def enabled? do
    Environment.cache_token_signing_key() != nil
  end

  @doc """
  Builds the token claims for a dispatch candidate. Pure — no signing,
  used directly by tests and by `mint/3`.
  """
  def claims(candidate, account, os) when os in [:macos, :linux] do
    now = DateTime.to_unix(DateTime.utc_now())

    %{
      "iss" => issuer(),
      "sub" => to_string(Map.get(candidate, :workflow_job_id, 0)),
      "account_id" => account.id,
      "account" => account.name,
      "repo" => Map.get(candidate, :repository, ""),
      "fleet" => Map.get(candidate, :fleet_name, ""),
      "os" => Atom.to_string(os),
      "ref" => branch_ref(Map.get(candidate, :head_branch, "")),
      "default_branch" => branch_ref(Map.get(candidate, :default_branch, "")),
      "base_ref" => branch_ref(Map.get(candidate, :base_ref, "")),
      "untrusted_fork" => Map.get(candidate, :untrusted_fork, 0) == 1,
      "head_sha" => Map.get(candidate, :head_sha, ""),
      "iat" => now,
      "exp" => now + @ttl_seconds
    }
  end

  @doc """
  Mints a signed cache token for a dispatch candidate, or
  `{:error, :disabled}` when no signing key is configured.
  """
  def mint(candidate, account, os) when os in [:macos, :linux] do
    case Environment.cache_token_signing_key() do
      nil ->
        {:error, :disabled}

      pem ->
        jwk = JOSE.JWK.from_pem(pem)
        jws = %{"alg" => "EdDSA"}
        jwt = JOSE.JWT.from_map(claims(candidate, account, os))
        {_, token} = jwk |> JOSE.JWT.sign(jws, jwt) |> JOSE.JWS.compact()
        {:ok, token}
    end
  end

  defp issuer do
    String.trim_trailing(Environment.app_url(), "/")
  end

  # Normalizes a branch name into a full ref. The gateway only needs the
  # write and read scopes to be consistent strings (a job writes under its
  # own ref and reads its own ref / base / default), so the exact ref
  # spelling matters less than that both sides agree.
  defp branch_ref(""), do: ""
  defp branch_ref(name) when is_binary(name), do: "refs/heads/" <> name
  defp branch_ref(_), do: ""
end
