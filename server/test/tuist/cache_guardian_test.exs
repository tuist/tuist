defmodule Tuist.CacheGuardianTest do
  use ExUnit.Case, async: true

  alias Tuist.CacheGuardian

  @signing_key """
  -----BEGIN PRIVATE KEY-----
  MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgNao/3q9zzchYXFLT
  RvHPzbm1hNO89b0285WkcrITd8ahRANCAASLOFCMFjBsh/zmFlBeW4cZo896Ifbo
  0xypYb0F/WijmQkcKGJ9x1BhMPnyNyad58vreVUb8xNg87p0JB7dr9eB
  -----END PRIVATE KEY-----
  """

  @rsa_key """
  -----BEGIN PRIVATE KEY-----
  MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDSAyjFfm1ry085
  pTVgRWTrNoPWhdLZQt9l/D1nUpp86czqa6uPSZCiV/BLSJhMxaUcEmR6LJbliQbX
  g6kVJfyTqebMN+SZx1Z9KZ4Y/Qf2irXx2rcOgKArSWSktij+DxfmDJF4G4mxbhw6
  E1rTEEGYe5cFdQTopG7KCmAx8ycrmVKCRPSlyzmEVFyOaCyNlmMdCID8mkdYw4wO
  YycEYJ7kJtm/6lkBRgbqzvKEj4sO/1ll8bdgA637qY5VirZ6Q8AKPBP/s9xy/jg3
  Lftofk3fDwnmhz6CcJvxVtela7eUDtVKcIv/9TU71lAoD2GtbNhgE/Amex8AzUBO
  Q1F6jANFAgMBAAECggEABzRqiqlKsbRY3x5m1WBWv6cFdi+YddxQc7GSnbUnbaT2
  Yw3B5fmHx7oCmWKVLv+81ANhhRDQixwHVboY6+EmEsl1DIktA4WOLF8SzcKof5xv
  SivPCeVUbrJm4dZfU6VK6ZksHcBmxI/a0gyQmhsS/7CFvtSD5ZihNbc4vkicOGeg
  kv8P5UibBWF/+GqT9fajBkdNgk2UsuOPPfXtGrPCmd3I5ZiorrvAYLp5H9FhKIdK
  b4LHdnlipjxNPs5cGAlpbzjt3MBYFe0JyZXtqUKMGmxSGZvDVhxM1hgHlPrW2CSW
  CJ1LRZIUX8pWXockcnKdHxJzXkY2aIJoRQZsz21thQKBgQDuWZ3N3HrHkkTfieuK
  rnUUAEWPN+Tv2RXgA5WUSEoZ0I2Zuy2f26EAabDNwiBdgiNUXkPyXLleNt2JD0Rr
  A0C5FnZBCNQSpv1kcdBCC/PLiqR8hsk9IjHmx2fE/qIQBmTLXS7TgJqWe29uzQNh
  uzOWgF+IOYtPu3T5DLOU5CttZwKBgQDhkFjJ6VQN0wfbiFpHZ0d0R2wq7yF4/yL5
  Gwc3zRtX6nNSr7uXP1P7GfnDLzqm+cY89XlvGBGEro+7l+u1uqBUuUg5egUT4/Ao
  +48S/MwXHOrG/w0ILyLHkIn2VjOHQatPIdLesdSvxRCrInmdKRkoyLcgYCMVcQ0K
  Z4ze895ycwKBgHoDfEne/Sde1E0OoHpM1nhXr0Qim9rAaXdUvmS7INvYLDSvYiq8
  Vs4MTMr3/nN/5DATVXsjRm1Zbszz+NVDRAW73utp5o5p17tsm+zDi5j9rzhkE25t
  K9h06cUpiLLlYwHMAOWapwgzxhaVco68MytvKfhlZNB7KOU5QFEPAMAvAoGAExy4
  +TrE/XrhEo/mHmC45DhdCPJEIs1zeCn7HZZKd9OMu/fZ7EHYatFToV8yGA3X5zhh
  drFSYqyrzxhbR4WtqiAc54nYPkw1ADP4doJnBJpVplDcGNJtnv03Q2Egcph03Hqg
  NHBa9h27gNSl+1QNJrCDG8IpltqCYVxOymFdetMCgYAz92qNF1dpLrE62fvswYm2
  KCUm+/8BQ7ihfgzD+iuAHX6uZeaDaAHAhQcAirOpqFM0Iprw+6bbbZw6DIkl4uFJ
  h/yEbvhBTAo2zfeaXnOdMqaKj2/4n7P7d0PlHJzzAFBU+wHVNp/apwtPm+MENiyP
  Pl+UiJLHh0qAfYvXs5kOcQ==
  -----END PRIVATE KEY-----
  """

  @p384_key """
  -----BEGIN PRIVATE KEY-----
  MIG2AgEAMBAGByqGSM49AgEGBSuBBAAiBIGeMIGbAgEBBDDxu4e/PSTIlPhixO1+
  Gov7W1dd6LG3Yjva4lPJr3Nk77SiXtAoOGJuLNmmBBRHVtShZANiAARZLaZN2az2
  aAmfcMQcOOf2qieDqJtmsbsUyHD1Q1P3XG+UdAjM6loGeIZzkKEVXyZEx3QWjOW0
  91cKURcnlYjjrjOkXORn0zzu2QFJj4g4OBVJ4KvFqwrxYDxovFaq6BQ=
  -----END PRIVATE KEY-----
  """

  describe "signing_jwk!/1" do
    test "reads a P-256 private key" do
      assert %JOSE.JWK{} = CacheGuardian.signing_jwk!(@signing_key)
    end

    # Each of these parses cleanly through JOSE.JWK.from_pem/1, so without the
    # checks below the server boots and then fails every token exchange.
    test "refuses a key of the wrong type" do
      assert_raise RuntimeError, ~r/RSA key/, fn -> CacheGuardian.signing_jwk!(@rsa_key) end
    end

    test "refuses a key on the wrong curve" do
      assert_raise RuntimeError, ~r/P-256/, fn -> CacheGuardian.signing_jwk!(@p384_key) end
    end

    test "refuses a key carrying only its public half" do
      public_only =
        @signing_key
        |> JOSE.JWK.from_pem()
        |> JOSE.JWK.to_public()
        |> JOSE.JWK.to_pem()
        |> elem(1)

      assert_raise RuntimeError, ~r/public key/, fn ->
        CacheGuardian.signing_jwk!(public_only)
      end
    end

    test "refuses something that is not a PEM at all" do
      assert_raise RuntimeError, ~r/readable PEM/, fn ->
        CacheGuardian.signing_jwk!("not a pem")
      end
    end
  end
end
