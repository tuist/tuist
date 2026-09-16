defmodule AtlasWeb.SubscriptionRateLimitTest do
  # The limiter's table is shared, so every test uses addresses and IPs unique
  # to itself rather than resetting global state.
  use ExUnit.Case, async: true

  alias AtlasWeb.SubscriptionRateLimit

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  test "allows a first request" do
    assert :ok = SubscriptionRateLimit.check(unique("10.0.0"), "#{unique("reader")}@example.com")
  end

  test "eventually denies a source that keeps submitting" do
    ip = unique("10.0.1")

    # Counted rather than hardcoded, so tuning the ceiling does not silently
    # turn this into a test of nothing.
    allowed =
      Enum.reduce_while(1..500, 0, fn _attempt, count ->
        case SubscriptionRateLimit.check(ip, "#{unique("reader")}@example.com") do
          :ok -> {:cont, count + 1}
          {:error, retry_after} when retry_after > 0 -> {:halt, count}
        end
      end)

    assert allowed > 0
    assert allowed < 500
  end

  test "denies a repeat for the same email even from a different address" do
    email = "#{unique("target")}@example.com"

    assert :ok = SubscriptionRateLimit.check(unique("10.0.2"), email)

    # A distributed attempt to bomb one inbox keeps every source under the
    # per-source limit, so only the per-address limit catches it.
    assert {:error, _retry_after} = SubscriptionRateLimit.check(unique("10.0.3"), email)
  end

  test "treats the email case-insensitively" do
    email = "#{unique("Mixed")}@Example.com"

    assert :ok = SubscriptionRateLimit.check(unique("10.0.4"), email)
    assert {:error, _retry_after} = SubscriptionRateLimit.check(unique("10.0.5"), String.downcase(email))
  end

  test "does not fall over when the email is missing" do
    assert SubscriptionRateLimit.check(unique("10.0.6"), nil) in [:ok, {:error, 900}]
  end
end
