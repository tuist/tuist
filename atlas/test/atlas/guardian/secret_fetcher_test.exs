defmodule Atlas.Guardian.SecretFetcherTest do
  use ExUnit.Case, async: true

  alias Atlas.Guardian.SecretFetcher
  alias Guardian.Token.Jwt

  @old String.duplicate("o", 64)
  @new String.duplicate("n", 64)

  # Stands in for a Guardian module's `config/1`, so each test picks its keys
  # without touching the shared application environment.
  defmodule Keys do
    @moduledoc false
    def config(key), do: Process.get({__MODULE__, key})
  end

  defp use_keys(current, previous) do
    Process.put({Keys, :secret_key}, current)
    Process.put({Keys, :previous_secret_key}, previous)
  end

  defp sign do
    {:ok, jwk} = SecretFetcher.fetch_signing_secret(Keys, [])

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
    with {:ok, jwk} <- SecretFetcher.fetch_verifying_secret(Keys, JOSE.JWT.peek_protected(token).fields, []),
         {true, _jwt, _jws} <- JOSE.JWT.verify_strict(jwk, ["HS512"], token) do
      true
    else
      _ -> false
    end
  end

  test "tokens stay valid across a rotation until the previous key is dropped" do
    use_keys(@old, nil)
    before_rotation = sign()
    without_kid = legacy_sign(@old)

    use_keys(@new, @old)
    after_rotation = sign()

    assert verifies?(before_rotation)
    assert verifies?(without_kid)
    assert verifies?(after_rotation)
    refute verifies?(legacy_sign(@new))

    use_keys(@new, nil)
    assert verifies?(after_rotation)
    refute verifies?(before_rotation)
    refute verifies?(without_kid)
  end

  test "Atlas.Guardian signs and verifies through the fetcher" do
    {:ok, token} = Jwt.create_token(Atlas.Guardian, %{"sub" => "1"}, [])

    assert JOSE.JWT.peek_protected(token).fields["kid"] == SecretFetcher.kid(Atlas.Guardian.config(:secret_key))
    assert {:ok, %{"sub" => "1"}} = Jwt.decode_token(Atlas.Guardian, token, [])
  end

  test "a blank previous key verifies nothing" do
    use_keys(@new, "   ")
    refute verifies?(legacy_sign("   "))
    assert verifies?(legacy_sign(@new))
  end
end
