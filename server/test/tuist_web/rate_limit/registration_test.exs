defmodule TuistWeb.RateLimit.RegistrationTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistWeb.RateLimit
  alias TuistWeb.RateLimit.Registration

  test "uses a hashed session token with the registration token bucket" do
    session_token = "session-token"
    session_key = :sha256 |> :crypto.hash(session_token) |> Base.url_encode64(padding: false)
    refill_rate = 1 / 300

    expect(RateLimit, :hit, fn key, [algorithm: :token_bucket, refill_rate: ^refill_rate, capacity: 3] ->
      assert key == "registration:" <> session_key
      {:allow, 2}
    end)

    assert Registration.hit(session_token) == {:allow, 2}
  end

  test "denies a missing session token" do
    assert Registration.hit(nil) == {:deny, 0}
  end
end
