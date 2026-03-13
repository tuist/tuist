defmodule Cache.ConfigTest do
  use ExUnit.Case, async: false

  describe "cache_endpoint/0" do
    test "returns hostname extracted from node name" do
      cache_endpoint = Cache.Config.cache_endpoint()
      assert is_binary(cache_endpoint)
      refute String.contains?(cache_endpoint, "@")
    end
  end
end
