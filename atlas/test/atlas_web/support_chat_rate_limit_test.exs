defmodule AtlasWeb.SupportChatRateLimitTest do
  use ExUnit.Case, async: true

  alias AtlasWeb.SupportChatRateLimit

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  test "allows an initial message" do
    assert :ok = SupportChatRateLimit.check(unique("10.0.0"), "#{unique("reader")}@example.com")
  end

  test "eventually denies a source that keeps sending messages" do
    ip = unique("10.0.1")

    allowed =
      Enum.reduce_while(1..1_000, 0, fn _attempt, count ->
        case SupportChatRateLimit.check(ip, "#{unique("reader")}@example.com") do
          :ok -> {:cont, count + 1}
          {:error, retry_after} when retry_after > 0 -> {:halt, count}
        end
      end)

    assert allowed > 0
    assert allowed < 1_000
  end

  test "treats an email address case-insensitively" do
    email = "#{unique("reader")}@Example.com"

    assert :ok = SupportChatRateLimit.check(unique("10.0.2"), email)
    assert :ok = SupportChatRateLimit.check(unique("10.0.3"), String.downcase(email))
  end
end
