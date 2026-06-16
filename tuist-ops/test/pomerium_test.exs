defmodule TuistOps.PomeriumTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistOps.Pomerium

  setup :verify_on_exit!

  setup do
    jwk = JOSE.JWK.generate_key({:ec, "P-256"})
    pub_pem = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem() |> unwrap()

    stub(TuistOps.Environment, :pomerium_jwt_public_key, fn -> pub_pem end)
    stub(TuistOps.Environment, :pomerium_audience, fn -> "ops.tuist.dev" end)
    stub(TuistOps.Environment, :dev_operator_email, fn -> nil end)

    {:ok, signer: jwk}
  end

  describe "verified_email/1" do
    test "returns the email from a valid Pomerium assertion", %{signer: signer} do
      conn = conn_with_assertion(mint(signer, claims()))
      assert Pomerium.verified_email(conn) == "marek@tuist.dev"
    end

    test "nil for an assertion signed by a different key" do
      other = JOSE.JWK.generate_key({:ec, "P-256"})
      conn = conn_with_assertion(mint(other, claims()))
      assert Pomerium.verified_email(conn) == nil
    end

    test "nil for an alg:none token" do
      conn = conn_with_assertion(none_token(claims()))
      assert Pomerium.verified_email(conn) == nil
    end

    test "nil for an HS256 token (alg confusion)" do
      {_meta, token} =
        "any-secret"
        |> JOSE.JWK.from_oct()
        |> JOSE.JWT.sign(%{"alg" => "HS256"}, claims())
        |> JOSE.JWS.compact()

      conn = conn_with_assertion(token)
      assert Pomerium.verified_email(conn) == nil
    end

    test "nil for the wrong audience", %{signer: signer} do
      conn = conn_with_assertion(mint(signer, claims(%{"aud" => "evil.example.com"})))
      assert Pomerium.verified_email(conn) == nil
    end

    test "nil for an expired assertion", %{signer: signer} do
      now = System.system_time(:second)
      conn = conn_with_assertion(mint(signer, claims(%{"exp" => now - 1})))
      assert Pomerium.verified_email(conn) == nil
    end

    test "ignores a bare X-Pomerium-Claim-Email header (forgeable)" do
      conn =
        Plug.Test.conn(:get, "/")
        |> Plug.Conn.put_req_header("x-pomerium-claim-email", "attacker@tuist.dev")

      assert Pomerium.verified_email(conn) == nil
    end

    test "fails closed when no public key is configured", %{signer: signer} do
      stub(TuistOps.Environment, :pomerium_jwt_public_key, fn -> nil end)
      conn = conn_with_assertion(mint(signer, claims()))
      assert Pomerium.verified_email(conn) == nil
    end

    test "falls back to the dev operator email when no assertion is present" do
      stub(TuistOps.Environment, :dev_operator_email, fn -> "dev@tuist.dev" end)
      assert Pomerium.verified_email(Plug.Test.conn(:get, "/")) == "dev@tuist.dev"
    end
  end

  defp claims(overrides \\ %{}) do
    now = System.system_time(:second)

    Map.merge(
      %{"aud" => "ops.tuist.dev", "email" => "marek@tuist.dev", "iat" => now, "exp" => now + 600},
      overrides
    )
  end

  defp mint(signer, claims) do
    {_meta, token} = signer |> JOSE.JWT.sign(%{"alg" => "ES256"}, claims) |> JOSE.JWS.compact()
    token
  end

  defp none_token(claims) do
    header =
      %{"alg" => "none", "typ" => "JWT"} |> Jason.encode!() |> Base.url_encode64(padding: false)

    payload = claims |> Jason.encode!() |> Base.url_encode64(padding: false)
    header <> "." <> payload <> "."
  end

  defp conn_with_assertion(token) do
    Plug.Test.conn(:get, "/") |> Plug.Conn.put_req_header("x-pomerium-jwt-assertion", token)
  end

  defp unwrap({_kty, pem}), do: pem
  defp unwrap(pem) when is_binary(pem), do: pem
end
