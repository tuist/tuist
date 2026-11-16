defmodule Tuist.OAuth2.SSOClientAssertion do
  @moduledoc """
  Signs the RFC 7523 client assertions Tuist presents to an organization's
  identity provider when the organization authenticates Tuist with
  `private_key_jwt` instead of storing a client secret with us.

  ## Keys

  The keys are RSA private keys configured as one PEM bundle in
  `TUIST_SSO_CLIENT_ASSERTION_PRIVATE_KEYS` (or `sso.client_assertion_private_keys`
  in the encrypted secrets). Every key in the bundle is published; the first
  one signs. RSA is required because Microsoft Entra ID only accepts RSA
  certificate credentials.

  Each key also has a self-signed X.509 certificate, because Entra ID cannot
  fetch a JWKS and needs a certificate uploaded instead. The certificate is
  derived deterministically from the key (fixed validity, serial from the key
  thumbprint, deterministic PKCS#1 v1.5 signature), so every replica serves
  the same certificate and its `x5t#S256` thumbprint stays stable.

  ## Rotation

  1. Append the new key to the bundle and deploy. Both keys are now in the JWKS
     and have certificates; the old key still signs.
  2. Organizations whose provider fetches the JWKS URL pick the new key up on
     their own. Organizations that pasted a JWKS or uploaded a certificate (all
     Entra ID organizations) add the new key's certificate or JWKS entry.
  3. Move the new key to the front of the bundle and deploy; it now signs.
  4. Once no organization relies on the old key, remove it and deploy.
  """

  alias Tuist.Environment
  alias Tuist.Time

  @assertion_ttl_seconds 5 * 60
  @client_assertion_type "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
  @minimum_rsa_bits 2048
  @certificate_subject "/O=Tuist/CN=Tuist SSO client"
  @certificate_not_before ~U[2026-01-01 00:00:00Z]
  @certificate_not_after ~U[2046-01-01 00:00:00Z]

  # Entra ID asks for PS256 assertions; Okta and most other providers only list
  # RS256 (and ECDSA), so everything else gets RS256 with the same key.
  @entra_token_hosts [
    "login.microsoftonline.com",
    "login.microsoftonline.us",
    "login.partner.microsoftonline.cn"
  ]

  def client_assertion_type, do: @client_assertion_type

  def available?, do: keys() != []

  @doc """
  Signs a single-use client assertion for `client_id` addressed to `token_url`,
  which both Okta and Entra ID require as the `aud` claim.
  """
  def sign(client_id, token_url) when is_binary(client_id) and is_binary(token_url) do
    case keys() do
      [] ->
        {:error, :sso_client_assertion_not_configured}

      [key | _] ->
        now = DateTime.to_unix(Time.utc_now())

        claims = %{
          "iss" => client_id,
          "sub" => client_id,
          "aud" => token_url,
          "jti" => UUIDv7.generate(),
          "iat" => now,
          "nbf" => now,
          "exp" => now + @assertion_ttl_seconds
        }

        header = %{
          "alg" => signing_algorithm(token_url),
          "typ" => "JWT",
          "kid" => key.kid,
          "x5t#S256" => key.certificate_thumbprint
        }

        {:ok, compact(key, header, claims)}
    end
  end

  def jwks do
    keys =
      Enum.map(keys(), fn key ->
        {_, public_map} = key.private_jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

        Map.merge(public_map, %{
          "kid" => key.kid,
          "use" => "sig",
          "alg" => "RS256",
          "x5c" => [Base.encode64(key.certificate_der)],
          "x5t#S256" => key.certificate_thumbprint
        })
      end)

    %{"keys" => keys}
  end

  def key_ids, do: Enum.map(keys(), & &1.kid)

  def certificate_pem(kid) do
    case Enum.find(keys(), &(&1.kid == kid)) do
      nil -> {:error, :not_found}
      key -> {:ok, :public_key.pem_encode([{:Certificate, key.certificate_der, :not_encrypted}])}
    end
  end

  # RFC 7518 §3.5 requires PS256's PSS salt to be as long as the hash (32
  # bytes). Erlang JOSE uses the maximum salt length instead, which strict
  # verifiers reject, so PS256 is signed here with the salt length pinned.
  defp compact(key, %{"alg" => "PS256"} = header, claims) do
    signing_input = encode_segment(header) <> "." <> encode_segment(claims)

    signature =
      :public_key.sign(signing_input, :sha256, key.private_key,
        rsa_padding: :rsa_pkcs1_pss_padding,
        rsa_pss_saltlen: 32
      )

    signing_input <> "." <> Base.url_encode64(signature, padding: false)
  end

  defp compact(key, header, claims) do
    {_, token} = key.private_jwk |> JOSE.JWT.sign(header, JOSE.JWT.from_map(claims)) |> JOSE.JWS.compact()
    token
  end

  defp encode_segment(map), do: map |> JSON.encode!() |> Base.url_encode64(padding: false)

  defp signing_algorithm(token_url) do
    if URI.parse(token_url).host in @entra_token_hosts, do: "PS256", else: "RS256"
  end

  # Parsing the bundle and signing the certificates costs a few RSA operations,
  # so the result is memoized per bundle on this node. The cache is derived
  # entirely from configuration and is safe to lose.
  defp keys do
    case Environment.sso_client_assertion_private_keys() do
      pem when is_binary(pem) and pem != "" ->
        cache_key = {__MODULE__, :crypto.hash(:sha256, pem)}

        case :persistent_term.get(cache_key, nil) do
          nil ->
            keys = parse_keys(pem)
            :persistent_term.put(cache_key, keys)
            keys

          keys ->
            keys
        end

      _ ->
        []
    end
  end

  defp parse_keys(pem) do
    pem
    |> :public_key.pem_decode()
    |> Enum.map(fn entry ->
      case :public_key.pem_entry_decode(entry) do
        {:RSAPrivateKey, _, modulus, _, _, _, _, _, _, _, _} = private_key ->
          if bit_size(:binary.encode_unsigned(modulus)) < @minimum_rsa_bits do
            raise ArgumentError, "SSO client assertion keys must be RSA keys of at least #{@minimum_rsa_bits} bits"
          end

          build_key(private_key)

        _ ->
          raise ArgumentError, "SSO client assertion keys must be RSA private keys"
      end
    end)
  end

  defp build_key(private_key) do
    private_jwk = JOSE.JWK.from_key(private_key)
    kid = JOSE.JWK.thumbprint(private_jwk)

    certificate_der =
      private_key
      |> X509.Certificate.self_signed(@certificate_subject,
        template: :server,
        hash: :sha256,
        serial: certificate_serial(kid),
        validity: X509.Certificate.Validity.new(@certificate_not_before, @certificate_not_after)
      )
      |> X509.Certificate.to_der()

    %{
      kid: kid,
      private_key: private_key,
      private_jwk: private_jwk,
      certificate_der: certificate_der,
      certificate_thumbprint: Base.url_encode64(:crypto.hash(:sha256, certificate_der), padding: false)
    }
  end

  # A positive 63-bit serial derived from the key, so the certificate is the
  # same on every replica and after every restart.
  defp certificate_serial(kid) do
    <<_::1, serial::63, _::binary>> = :crypto.hash(:sha256, kid)
    max(serial, 1)
  end
end
