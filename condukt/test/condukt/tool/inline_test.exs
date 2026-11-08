defmodule Condukt.Tool.InlineTest do
  use ExUnit.Case, async: true

  test "builds an inline tool struct with the required fields" do
    tool =
      Condukt.tool(
        name: "echo",
        description: "Echoes the input text.",
        parameters: %{type: "object", properties: %{text: %{type: "string"}}, required: ["text"]},
        call: fn %{"text" => text}, _ctx -> {:ok, text} end
      )

    assert %Condukt.Tool.Inline{name: "echo"} = tool
    assert tool.description =~ "Echoes"
    assert tool.parameters.required == ["text"]
    assert is_function(tool.call, 2)
  end

  test "raises a clear error when a required field is missing" do
    assert_raise KeyError, fn ->
      Condukt.tool(name: "no-call")
    end
  end
end
