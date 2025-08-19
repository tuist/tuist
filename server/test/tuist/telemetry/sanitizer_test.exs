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

  describe "sanitize_metadata/1" do
    test "sanitizes all values in a map" do
      error = %Redix.ConnectionError{reason: :tcp_closed}

      metadata = %{
        name: "test",
        status: 200,
        error: error,
        list: [1, 2, 3]
      }

      result = Sanitizer.sanitize_metadata(metadata)

      assert result.name == "test"
      assert result.status == 200
      assert result.error == "Redix.ConnectionError"
      assert result.list == "[1, 2, 3]"
    end

    test "returns non-map values unchanged" do
      assert Sanitizer.sanitize_metadata("test") == "test"
      assert Sanitizer.sanitize_metadata(123) == 123
    end
  end
end
