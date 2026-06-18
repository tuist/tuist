defmodule TuistOps.Pomerium do
  @moduledoc """
  Resolves the operator identity in front of the HTML surface
  (`/grants`, `/audit`) from the signature Pomerium puts on each
  request, not from a plain header.

  Pomerium signs a per-request JWT (`X-Pomerium-Jwt-Assertion`, ES256)
  with its signing key and publishes the matching public key. We verify
  that signature offline and read the `email` claim from it. The bare
  `X-Pomerium-Claim-Email` header is deliberately NOT trusted: anything
  that can reach this app directly over the tailnet (the Service is
  tailnet-exposed) can forge it, bypassing Pomerium entirely.

  Fail-closed. No assertion, a bad signature, the wrong audience, an
  expired token, or an unconfigured public key all yield `nil` — the
  controller then renders 401 and no grant is minted. In local
  development there is no Pomerium, so identity falls back to
  `TUIST_OPS_DEV_OPERATOR_EMAIL` (nil in production).
  """

  alias TuistOps.Environment

  require Logger

  @assertion_header "x-pomerium-jwt-assertion"

  @doc """
  The verified operator email for this request, or `nil`.
  """
  def verified_email(conn) do
    case Plug.Conn.get_req_header(conn, @assertion_header) do
      [token | _] when is_binary(token) and byte_size(token) > 0 ->
        verify(token)

      _ ->
        # No Pomerium assertion: only the dev fallback can supply an
        # identity (nil in production → fail closed).
        Environment.dev_operator_email()
    end
  end

  defp verify(token) do
    with {:ok, jwk} <- public_jwk(),
         # ES256-strict: never honour the token's own `alg`, so a
         # forged `none`/HS* token can't be accepted.
         {true, %JOSE.JWT{fields: fields}, _jws} <- JOSE.JWT.verify_strict(jwk, ["ES256"], token),
         :ok <- check_audience(fields),
         :ok <- check_not_expired(fields),
         email when is_binary(email) and byte_size(email) > 0 <- Map.get(fields, "email") do
      email
    else
      _ ->
        Logger.warning("pomerium assertion rejected")
        nil
    end
  end

  defp public_jwk do
    case Environment.pomerium_jwt_public_key() do
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

  defp check_audience(fields) do
    expected = Environment.pomerium_audience()

    case Map.get(fields, "aud") do
      ^expected -> :ok
      auds when is_list(auds) -> if expected in auds, do: :ok, else: {:error, :bad_audience}
      _ -> {:error, :bad_audience}
    end
  end

  defp check_not_expired(%{"exp" => exp}) when is_integer(exp) do
    if exp > System.system_time(:second), do: :ok, else: {:error, :expired}
  end

  defp check_not_expired(_), do: {:error, :missing_exp}
end
