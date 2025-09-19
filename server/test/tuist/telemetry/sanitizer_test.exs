defmodule Tuist.Telemetry.SanitizerTest do
  use ExUnit.Case

  alias Tuist.Telemetry.Sanitizer

  describe "sanitize_value/1" do
    test "handles basic types correctly" do
      assert Sanitizer.sanitize_value("string") == "string"
      assert Sanitizer.sanitize_value(:atom) == :atom
      assert Sanitizer.sanitize_value(123) == 123
      assert Sanitizer.sanitize_value(1.23) == 1.23
      assert Sanitizer.sanitize_value(true) == true
      assert Sanitizer.sanitize_value(false) == false
    end

    test "handles structs by returning module name" do
      error = %Redix.ConnectionError{reason: :tcp_closed}
      result = Sanitizer.sanitize_value(error)
      assert result == "Redix.ConnectionError"
    end

    test "handles lists by inspecting them" do
      result = Sanitizer.sanitize_value([1, 2, 3])
      assert result == "[1, 2, 3]"

      result = Sanitizer.sanitize_value(~c"hello")
      assert result == "~c\"hello\""
    end

    test "handles maps and other types via inspect" do
      result = Sanitizer.sanitize_value(%{key: "value"})
      assert result == "%{key: \"value\"}"
    end
  end
end
