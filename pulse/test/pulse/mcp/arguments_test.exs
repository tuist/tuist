defmodule Pulse.MCP.ArgumentsTest do
  use Pulse.Test.Case, async: true

  alias Pulse.MCP.Arguments

  @schema %{
    "type" => "object",
    "maxProperties" => 2,
    "propertyNames" => %{"type" => "string", "minLength" => 1, "maxLength" => 3},
    "additionalProperties" => %{"type" => "string", "minLength" => 1, "maxLength" => 3}
  }

  test "published dictionary constraints are enforced recursively" do
    assert :ok = Arguments.validate(%{"one" => "two"}, @schema)
    assert :ok = Arguments.validate(%{"é" => "界"}, @schema)
    array = %{"type" => "array", "maxItems" => 2, "items" => %{"type" => "string"}}
    assert :ok = Arguments.validate([], array)
    assert :ok = Arguments.validate(["a", "b"], array)

    assert {:error, {:invalid_arguments, "arguments must contain at most 2 items"}} =
             Arguments.validate(["a", "b", "c"], array)

    assert {:error, {:invalid_arguments, _}} = Arguments.validate([1], array)

    for value <- [
          %{"" => "a"},
          %{"long" => "a"},
          %{"a" => "long"},
          %{"a" => ""},
          %{"a" => 1},
          %{"a" => nil},
          %{a: "b"},
          %{"a" => "b", "c" => "d", "e" => "f"}
        ] do
      assert {:error, {:invalid_arguments, _}} = Arguments.validate(value, @schema)
    end
  end

  test "lengths count Unicode code points rather than grapheme clusters" do
    schema = %{"type" => "string", "maxLength" => 1}
    assert :ok = Arguments.validate("é", schema)
    assert {:error, {:invalid_arguments, _}} = Arguments.validate("e\u0301", schema)
    assert {:error, {:invalid_arguments, _}} = Arguments.validate("👨‍👩‍👧‍👦", schema)
    assert {:error, {:invalid_arguments, _}} = Arguments.validate(<<255>>, schema)
  end

  test "declared properties override the additional-value schema" do
    schema = Map.put(@schema, "properties", %{"num" => %{"type" => "integer"}})
    assert :ok = Arguments.validate(%{"num" => 1, "a" => "b"}, schema)
    assert {:error, {:invalid_arguments, _}} = Arguments.validate(%{"num" => "bad"}, schema)
    assert {:error, {:invalid_arguments, _}} = Arguments.validate(%{"num" => 1, "a" => 2}, schema)
  end
end
