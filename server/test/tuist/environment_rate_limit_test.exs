defmodule Tuist.EnvironmentRateLimitTest do
  use ExUnit.Case, async: true

  alias Tuist.Environment

  test "the runtime outage allowance accepts a deployment envelope of at least five" do
    assert Environment.parse_rate_limit_fallback_replicas("5") == 5
    assert Environment.parse_rate_limit_fallback_replicas("11") == 11

    for value <- ["4", "-1", "5.5", "invalid"] do
      assert_raise ArgumentError, fn -> Environment.parse_rate_limit_fallback_replicas(value) end
    end
  end
end
