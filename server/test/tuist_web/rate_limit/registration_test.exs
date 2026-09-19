defmodule TuistWeb.RateLimit.RegistrationTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistWeb.RateLimit
  alias TuistWeb.RateLimit.Registration

  test "uses a hashed session token with the registration token bucket" do
    session_token = "session-token"
    session_key = :sha256 |> :crypto.hash(session_token) |> Base.url_encode64(padding: false)
    refill_rate = 1 / 300

    expect(RateLimit, :hit, fn key, [algorithm: :token_bucket, refill_rate: ^refill_rate, capacity: 10] ->
      assert key == "registration:" <> session_key
      {:allow, 9}
    end)

    assert Registration.hit(session_token) == {:allow, 9}
  end

  test "signals a missing session token distinctly from a rate-limit denial" do
    assert Registration.hit(nil) == {:error, :missing_session}
    assert Registration.hit("") == {:error, :missing_session}
  end
end
