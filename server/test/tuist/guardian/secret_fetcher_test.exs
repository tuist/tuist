defmodule Tuist.Guardian.SecretFetcherTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Guardian.Token.Jwt
  alias Tuist.Guardian.SecretFetcher

  @old String.duplicate("o", 64)
  @new String.duplicate("n", 64)

  defp use_keys(current, previous) do
    stub(Tuist.Guardian, :config, fn
      :secret_key -> current
      :previous_secret_key -> previous
    end)
  end

  # Signs as Guardian does: with the fetcher's key, copying its `kid` into the header.
  defp sign do
    {:ok, jwk} = SecretFetcher.fetch_signing_secret(Tuist.Guardian, [])

    {_jws, token} =
      jwk |> JOSE.JWT.sign(%{"alg" => "HS512", "kid" => jwk.fields["kid"]}, %{"sub" => "1"}) |> JOSE.JWS.compact()

    token
  end

  defp legacy_sign(key) do
    {_jws, token} =
      key |> JOSE.JWK.from_oct() |> JOSE.JWT.sign(%{"alg" => "HS512"}, %{"sub" => "1"}) |> JOSE.JWS.compact()

    token
  end

  defp verifies?(token) do
    with {:ok, jwk} <- SecretFetcher.fetch_verifying_secret(Tuist.Guardian, JOSE.JWT.peek_protected(token).fields, []),
         {true, _jwt, _jws} <- JOSE.JWT.verify_strict(jwk, ["HS512"], token) do
      true
    else
      _ -> false
    end
  end

  test "tokens stay valid across a rotation until the previous key is dropped" do
    use_keys(@old, nil)
    before_rotation = sign()
    # Issued before keys had ids.
    without_kid = legacy_sign(@old)

    use_keys(@new, @old)
    after_rotation = sign()

    assert verifies?(before_rotation)
    assert verifies?(without_kid)
    assert verifies?(after_rotation)
    refute verifies?(legacy_sign(@new))
    assert JOSE.JWT.peek_protected(after_rotation).fields["kid"] == SecretFetcher.kid(@new)

    use_keys(@new, nil)
    assert verifies?(after_rotation)
    refute verifies?(before_rotation)
    refute verifies?(without_kid)
  end

  test "Tuist.Guardian signs and verifies through the fetcher" do
    {:ok, token} = Jwt.create_token(Tuist.Guardian, %{"sub" => "1"}, [])

    assert JOSE.JWT.peek_protected(token).fields["kid"] == SecretFetcher.kid(Tuist.Guardian.config(:secret_key))
    assert {:ok, %{"sub" => "1"}} = Jwt.decode_token(Tuist.Guardian, token, [])
  end

  test "a blank previous key verifies nothing" do
    use_keys(@new, "   ")
    refute verifies?(legacy_sign("   "))
    assert verifies?(legacy_sign(@new))
  end

  test "refuses a kid that names neither key" do
    use_keys(String.duplicate("x", 64), nil)
    token = sign()

    use_keys(@new, @old)
    refute verifies?(token)
  end
end
