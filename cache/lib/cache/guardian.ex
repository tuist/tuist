defmodule Cache.Guardian do
  @moduledoc """
  Verifies JWTs minted by the main Tuist server.

  Two kinds of key can answer for a token, and each answers only for its own
  algorithm:

    * The public halves of the server's cache-token keypair
      (`CACHE_TOKEN_PUBLIC_KEY`) verify ES256 tokens. A node holding them can
      read a cache token and cannot mint one.
    * The legacy symmetric key (`GUARDIAN_SECRET_KEY`) verifies HS512 tokens.
      It is the key the server signs API credentials with, so it is optional and
      on its way out.

  The token's header only picks which of the two to try; the algorithm each key
  accepts is fixed here, so a token can never have a public key's PEM read as
  an HMAC secret.
  """

  use Guardian, otp_app: :cache

  @public_key_algorithm "ES256"
  @legacy_algorithm "HS512"

  def subject_for_token(_resource, %{"sub" => sub}) do
    {:ok, sub}
  end

  def resource_from_claims(_claims) do
    # Not used for verification-only use case
    {:error, :not_implemented}
  end

  @doc """
  Verifies the token's signature with the key its algorithm calls for, then its
  standard claims.
  """
  def verify_token(token) when is_binary(token) do
    case peek_header(token) do
      %{"alg" => @public_key_algorithm} -> verify_with_public_keys(token, Cache.Config.cache_token_public_keys())
      %{"alg" => @legacy_algorithm} -> verify_with_legacy_secret(token, Cache.Config.guardian_secret_key())
      _ -> {:error, :invalid_token}
    end
  end

  defp verify_with_public_keys(_token, []), do: {:error, :invalid_token}

  # Several keys are held while a rotation publishes the next one alongside the
  # current one, and a token signed by either is good.
  defp verify_with_public_keys(token, keys) do
    Enum.reduce_while(keys, {:error, :invalid_token}, fn key, failure ->
      case decode_and_verify(token, %{"iss" => "tuist"}, secret: key, allowed_algos: [@public_key_algorithm]) do
        {:ok, claims} -> {:halt, {:ok, claims}}
        {:error, _reason} -> {:cont, failure}
      end
    end)
  end

  defp verify_with_legacy_secret(_token, nil), do: {:error, :invalid_token}

  defp verify_with_legacy_secret(token, secret) do
    decode_and_verify(token, %{}, secret: secret, allowed_algos: [@legacy_algorithm])
  end

  # Read raw: Guardian's and JOSE's peeks both drop `alg` from the fields they
  # return. Nothing read here is trusted; it only picks the key to try.
  defp peek_header(token) do
    token |> JOSE.JWS.peek_protected() |> JOSE.decode()
  rescue
    _ -> nil
  catch
    _kind, _reason -> nil
  end
end
