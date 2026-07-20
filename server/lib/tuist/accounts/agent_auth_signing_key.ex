defmodule Tuist.Accounts.AgentAuthSigningKey do
  @moduledoc """
  Signs and verifies the service identity assertions used by auth.md.

  The P-256 key is deterministically derived from Tuist's token-signing secret.
  This keeps the key stable across replicas and restarts while separating it
  from the symmetric key used by Guardian.
  """

  alias Tuist.Accounts.AgentRegistration
  alias Tuist.Environment
  alias Tuist.Time

  @assertion_ttl_seconds 60 * 60
  @p256_order 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551

  def assertion_ttl_seconds, do: @assertion_ttl_seconds

  def sign(%AgentRegistration{} = registration, issuer, opts \\ []) do
    now = Time.utc_now()
    expires_at = DateTime.add(now, @assertion_ttl_seconds, :second)

    claims =
      %{
        "iss" => issuer,
        "sub" => external_registration_id(registration),
        "aud" => issuer,
        "jti" => "jti_#{UUIDv7.generate()}",
        "iat" => DateTime.to_unix(now),
        "exp" => DateTime.to_unix(expires_at),
        "agent_auth_version" => Keyword.get(opts, :version, 1)
      }
      |> maybe_put("email", Keyword.get(opts, :email))
      |> maybe_put("email_verified", Keyword.get(opts, :email_verified))
      |> maybe_put("amr", Keyword.get(opts, :amr))

    header = %{"alg" => "ES256", "kid" => key_id(), "typ" => "oauth-id-jag+jwt"}
    {_, token} = private_jwk() |> JOSE.JWT.sign(header, JOSE.JWT.from_map(claims)) |> JOSE.JWS.compact()

    {:ok, %{assertion: token, expires_at: expires_at, claims: claims}}
  end

  def verify(token, issuer) when is_binary(token) and is_binary(issuer) do
    with {:ok, header} <- peek_header(token),
         :ok <- validate_header(header),
         {true, %JOSE.JWT{fields: claims}, _jws} <-
           JOSE.JWT.verify_strict(public_jwk(), ["ES256"], token),
         :ok <- validate_claims(claims, issuer) do
      {:ok, claims}
    else
      _ -> {:error, :invalid_grant}
    end
  rescue
    _ -> {:error, :invalid_grant}
  end

  def verify(_token, _issuer), do: {:error, :invalid_grant}

  def jwks do
    {_, public_map} = JOSE.JWK.to_public_map(private_jwk())

    key =
      public_map
      |> Map.put("kid", key_id())
      |> Map.put("alg", "ES256")
      |> Map.put("use", "sig")

    %{"keys" => [key]}
  end

  defp validate_header(%{"alg" => "ES256", "typ" => "oauth-id-jag+jwt", "kid" => kid}) do
    if kid == key_id(), do: :ok, else: {:error, :invalid_grant}
  end

  defp validate_header(_header), do: {:error, :invalid_grant}

  defp validate_claims(%{"iss" => issuer, "aud" => audience, "sub" => "reg_" <> _, "jti" => jti, "exp" => exp}, issuer)
       when audience == issuer and is_binary(jti) and is_integer(exp) do
    if exp > DateTime.to_unix(Time.utc_now()), do: :ok, else: {:error, :invalid_grant}
  end

  defp validate_claims(_claims, _issuer), do: {:error, :invalid_grant}

  defp peek_header(token) do
    with [encoded_header, _, _] <- String.split(token, "."),
         {:ok, json} <- Base.url_decode64(encoded_header, padding: false),
         {:ok, header} <- JSON.decode(json) do
      {:ok, header}
    else
      _ -> {:error, :invalid_grant}
    end
  end

  defp private_jwk do
    private_key = derive_private_key(Environment.secret_key_tokens())
    {public_key, private_key} = :crypto.generate_key(:ecdh, :secp256r1, private_key)
    <<4, x::binary-size(32), y::binary-size(32)>> = public_key

    JOSE.JWK.from_map(%{
      "kty" => "EC",
      "crv" => "P-256",
      "x" => Base.url_encode64(x, padding: false),
      "y" => Base.url_encode64(y, padding: false),
      "d" => Base.url_encode64(private_key, padding: false)
    })
  end

  defp public_jwk do
    JOSE.JWK.to_public(private_jwk())
  end

  defp key_id, do: JOSE.JWK.thumbprint(private_jwk())

  defp derive_private_key(secret) do
    value =
      :sha256
      |> :crypto.hash("tuist-auth-md-signing-key\0#{secret}")
      |> :binary.decode_unsigned()
      |> rem(@p256_order - 1)
      |> Kernel.+(1)

    value
    |> :binary.encode_unsigned()
    |> left_pad(32)
  end

  defp left_pad(binary, size) when byte_size(binary) < size do
    :binary.copy(<<0>>, size - byte_size(binary)) <> binary
  end

  defp left_pad(binary, _size), do: binary

  defp external_registration_id(registration), do: "reg_#{registration.id}"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
