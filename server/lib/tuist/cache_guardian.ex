defmodule Tuist.CacheGuardian do
  @moduledoc """
  Signs the short-lived tokens cache nodes authorize from.

  Separate from `Tuist.Guardian` because the two keys answer to different
  holders. A cache node is given the public half of this keypair so it can read
  a token where the request lands instead of asking here, which means every node
  can read every cache token and none of them can mint one. `Tuist.Guardian`
  signs with a symmetric key that also signs API credentials, so a node holding
  it could mint those; that key never leaves the server.

  Holding the key and signing with it are switched on separately, in that order.
  See `configured?/0` and `signing?/0`.
  """

  use Guardian, otp_app: :tuist

  alias Tuist.Environment

  # Written out rather than aliased: `Guardian` in this module is the library
  # this one is built on, not the sibling it delegates to.
  defdelegate subject_for_token(resource, claims), to: Tuist.Guardian

  # Nothing signed here is ever an API credential. `Tuist.Guardian` refuses the
  # same token type for the same reason.
  def resource_from_claims(_claims), do: {:error, :invalid_token_type}

  @doc """
  Whether this replica holds the keypair, and can therefore verify tokens signed
  with it.
  """
  def configured? do
    :tuist
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:secret_key)
    |> then(&(not is_nil(&1)))
  end

  @doc """
  Whether this replica signs cache tokens with the keypair rather than with
  `Tuist.Guardian`.

  Gated behind `configured?/0` on purpose, and switched on only once every
  replica holds the key: a replica that does not hold it cannot verify what a
  replica that does has signed, and would report a perfectly good token
  inactive.
  """
  def signing? do
    configured?() and Environment.cache_token_signing_enabled?()
  end

  @doc """
  Reads the signing key from a PEM, refusing anything that is not a P-256
  private key.

  `JOSE.JWK.from_pem/1` parses a public key, an RSA key or another curve just as
  willingly, and every one of those boots cleanly and then fails the token
  exchange on the first request. The structural checks name the mistake; the
  signature that follows is what proves the key can actually do the job.
  """
  def signing_jwk!(pem) do
    jwk =
      case JOSE.JWK.from_pem(pem) do
        %JOSE.JWK{} = jwk ->
          jwk

        _ ->
          raise "TUIST_SECRET_KEY_CACHE_TOKENS is not a readable PEM key"
      end

    {_modules, map} = JOSE.JWK.to_map(jwk)

    cond do
      map["kty"] != "EC" ->
        raise "TUIST_SECRET_KEY_CACHE_TOKENS is a #{map["kty"]} key; cache tokens are signed with ES256, which needs an EC key"

      map["crv"] != "P-256" ->
        raise "TUIST_SECRET_KEY_CACHE_TOKENS is on curve #{map["crv"]}; ES256 needs P-256"

      is_nil(map["d"]) ->
        raise "TUIST_SECRET_KEY_CACHE_TOKENS carries only a public key; signing needs the private half"

      true ->
        signing_jwk_that_signs!(jwk)
    end
  end

  defp signing_jwk_that_signs!(jwk) do
    {_modules, token} =
      jwk
      |> JOSE.JWT.sign(%{"alg" => "ES256"}, %{"probe" => true})
      |> JOSE.JWS.compact()

    case JOSE.JWT.verify_strict(jwk, ["ES256"], token) do
      {true, _claims, _jws} -> jwk
      _ -> raise "TUIST_SECRET_KEY_CACHE_TOKENS did not produce a verifiable ES256 signature"
    end
  end
end
