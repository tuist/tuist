defmodule Tuist.UUIDv7Test do
  use ExUnit.Case, async: true

  describe "valid?/1" do
    test "returns true for a valid UUIDv7" do
      assert Tuist.UUIDv7.valid?("a7b3b6e0-7b7d-7e7d-7e7d-7e7d7e7d7e7d") == true
    end

    test "returns false for an invalid UUIDv7" do
      assert Tuist.UUIDv7.valid?("a7b3b6e0-7b7d-7e7d-7e7d-7e7d7e7d7e7d7e7d") == false
    end
  end
end
