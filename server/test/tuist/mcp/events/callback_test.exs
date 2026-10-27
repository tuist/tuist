defmodule Tuist.MCP.Events.CallbackTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.MCP.Events.Callback
  alias Tuist.OAuth2.SSRFGuard

  @secret "whsec_MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY="

  setup :set_mimic_from_context

  test "accepts only Standard Webhooks secrets of the required length" do
    assert Callback.valid_secret?(@secret)
    refute Callback.valid_secret?("whsec_c2hvcnQ=")
    refute Callback.valid_secret?("not-a-secret")
  end

  test "signs the message ID, attempt timestamp, and exact body bytes" do
    assert Callback.sign("evt_123", 1_700_000_000, ~s({"type":"test_case.marked_flaky"}), @secret) ==
             "v1,2BKyEseVfhiGm5WQZw2iBIT2bf+QxU+MR23LgB9p0x4="
  end

  test "stops a callback that keeps the connection open" do
    stub(SSRFGuard, :pin, fn _url -> {:ok, "https://203.0.113.10/events", "example.com"} end)
    stub(SSRFGuard, :connect_options, fn _host -> [] end)
    stub(Req, :post, fn _url, _options -> Process.sleep(to_timeout(second: 10)) end)

    assert {:error, :timeout} =
             Callback.post("https://example.com/events", @secret, "sub_1", "evt_1", "{}")
  end

  test "returns callback task errors without exiting the caller" do
    stub(SSRFGuard, :pin, fn _url -> raise "failed to resolve callback" end)

    assert {:error, {%RuntimeError{message: "failed to resolve callback"}, _stacktrace}} =
             Callback.post("https://example.com/events", @secret, "sub_1", "evt_1", "{}")
  end
end
