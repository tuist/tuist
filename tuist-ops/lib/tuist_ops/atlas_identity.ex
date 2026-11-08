defmodule TuistOps.AtlasIdentity do
  @moduledoc """
  Verifies that a request comes from Atlas, using the projected
  Kubernetes ServiceAccount token Atlas sends as its bearer.

  Atlas runs in its own cluster, so its token is verified offline
  against that cluster's pinned public JWKS, the same key the Tuist
  server and Pulse pin. The token must be RS256, signed by a pinned
  key, carry the configured issuer and the `ops.tuist.dev` audience
  (so a token Atlas sends to the Tuist server or Pulse is useless
  here), live no longer than an hour, and name Atlas' ServiceAccount.

  Fail closed: an unconfigured JWKS rejects every token.
  """

  alias TuistOps.Environment

  require Logger

  @clock_skew_seconds 60
  @max_token_ttl_seconds 3600

  @doc "Returns `:ok` when `token` is a valid Atlas token, else `{:error, reason}`."
  def verify(token) when is_binary(token) and token != "" do
    with {:ok, keys} <- keys(),
         {:ok, claims} <- verify_signature(token, keys),
         :ok <- check_claims(claims, System.system_time(:second)) do
      :ok
    else
      {:error, reason} = error ->
        Logger.warning("atlas identity rejected: #{inspect(reason)}")
        error
    end
  end

  def verify(_token), do: {:error, :missing_token}

  defp keys do
    with jwks when is_binary(jwks) and jwks != "" <- Environment.atlas_token_jwks(),
         {:ok, %{"keys" => [_ | _] = keys}} <- JSON.decode(jwks) do
      {:ok, keys}
    else
      _ -> {:error, :not_configured}
    end
  end

  # Kubernetes always sets `kid`; a token without one, or naming a key
  # we don't pin, is rejected instead of tried against every key.
  defp verify_signature(token, keys) do
    with %{"kid" => kid} when is_binary(kid) <- peek_header(token),
         %{} = key <- Enum.find(keys, &(&1["kid"] == kid)),
         {true, %JOSE.JWT{fields: claims}, _jws} <-
           JOSE.JWT.verify_strict(JOSE.JWK.from_map(key), ["RS256"], token) do
      {:ok, claims}
    else
      _ -> {:error, :invalid_signature}
    end
  rescue
    _ -> {:error, :invalid_signature}
  end

  defp peek_header(token) do
    token |> JOSE.JWS.peek_protected() |> JSON.decode!()
  end

  defp check_claims(claims, now) do
    cond do
      claims["iss"] != Environment.atlas_token_issuer() -> {:error, :bad_issuer}
      not audience?(claims["aud"], Environment.atlas_token_audience()) -> {:error, :bad_audience}
      claims["sub"] != Environment.atlas_service_account() -> {:error, :bad_subject}
      true -> check_times(claims["exp"], claims["iat"], now)
    end
  end

  defp check_times(exp, iat, now) when is_integer(exp) and is_integer(iat) do
    cond do
      exp <= now - @clock_skew_seconds -> {:error, :expired}
      iat > now + @clock_skew_seconds -> {:error, :not_yet_valid}
      exp - iat > @max_token_ttl_seconds -> {:error, :ttl_too_long}
      true -> :ok
    end
  end

  defp check_times(_exp, _iat, _now), do: {:error, :bad_time_claims}

  defp audience?(aud, expected) when is_binary(aud), do: aud == expected
  defp audience?(auds, expected) when is_list(auds), do: expected in auds
  defp audience?(_aud, _expected), do: false
end
