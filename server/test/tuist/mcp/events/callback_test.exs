defmodule Tuist.MCP.Events.CallbackTest do
  use ExUnit.Case, async: true

  alias Tuist.MCP.Events.Callback

  @secret "whsec_MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY="

  test "accepts only Standard Webhooks secrets of the required length" do
    assert Callback.valid_secret?(@secret)
    refute Callback.valid_secret?("whsec_c2hvcnQ=")
    refute Callback.valid_secret?("not-a-secret")
  end

  test "signs the message ID, attempt timestamp, and exact body bytes" do
    assert Callback.sign("evt_123", 1_700_000_000, ~s({"type":"test_case.marked_flaky"}), @secret) ==
             "v1,2BKyEseVfhiGm5WQZw2iBIT2bf+QxU+MR23LgB9p0x4="
  end
end
