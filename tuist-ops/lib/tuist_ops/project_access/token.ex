defmodule TuistOps.ProjectAccess.Token do
  @moduledoc """
  Mints the signed grant token the customer `server/` verifies
  offline before honouring operator access to a customer project.

  ## Why a signed token (and not a server→ops call)

  The token is an **Ed25519 (EdDSA) JWS**. ops holds the private key
  (`PROJECT_ACCESS_SIGNING_KEY`); the customer server holds only the
  public key and verifies with it — no runtime call back to ops, so
  the two services stay on separate failure domains (the same
  decoupling the JIT kubectl path is built on). Asymmetric, not a
  shared HMAC secret, so even a compromised customer server can't
  mint a grant for itself.

  ## Claims

      iss            "ops.tuist.dev"
      aud            the customer server audience for this env
      sub            operator email (from X-Pomerium-Claim-Email)
      account_handle the customer account the grant is scoped to
      tier           "read" | "admin"
      reason         the justification the operator typed
      jti            the Grant row id (audit join key)
      iat / exp      issued-at / expiry (the grant's expires_at)

  The customer server pins `iss`/`aud`, enforces an `EdDSA`-only
  verification, and caps `exp - iat` so a long-lived token can't be
  minted. See `TuistWeb.OperatorGrant.verify/1` on the server side.
  """

  alias TuistOps.Environment
  alias TuistOps.ProjectAccess.Grant

  @issuer "ops.tuist.dev"

  @doc """
  Mints the compact EdDSA JWS for a persisted grant. Raises if the
  signing key is missing or malformed — a grant we can't sign is a
  bug, not a recoverable runtime condition.
  """
  def mint(%Grant{} = grant) do
    claims = %{
      "iss" => @issuer,
      "aud" => Environment.operator_grant_audience(),
      "sub" => grant.requester_email,
      "account_handle" => grant.account_handle,
      "tier" => grant.tier,
      "reason" => grant.reason,
      "jti" => to_string(grant.id),
      "iat" => DateTime.to_unix(DateTime.utc_now()),
      "exp" => DateTime.to_unix(grant.expires_at)
    }

    {_meta, token} =
      signing_jwk()
      |> JOSE.JWT.sign(%{"alg" => "EdDSA"}, claims)
      |> JOSE.JWS.compact()

    token
  end

  defp signing_jwk do
    case Environment.project_access_signing_key() do
      pem when is_binary(pem) and byte_size(pem) > 0 ->
        JOSE.JWK.from_pem(pem)

      _ ->
        raise "PROJECT_ACCESS_SIGNING_KEY is not configured; cannot sign operator grant tokens"
    end
  end
end
