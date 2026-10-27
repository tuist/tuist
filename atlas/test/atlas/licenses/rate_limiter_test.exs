defmodule Atlas.Licenses.RateLimiterTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Licenses.RateLimiter
  alias Atlas.RateLimit

  test "uses the shared license namespace and configured allowance" do
    identifier = :crypto.strong_rand_bytes(32)

    expect(RateLimit, :hit, fn key, window, limit ->
      assert key == "license_validation:" <> identifier
      assert window == 60_000
      assert limit == 60
      {:allow, 1}
    end)

    assert :ok = RateLimiter.check(identifier)
  end

  test "rounds shared retry durations up to whole seconds" do
    expect(RateLimit, :hit, fn _key, _window, _limit -> {:deny, 1_001} end)
    assert {:error, 2} = RateLimiter.check("opaque-identifier")
  end
end
