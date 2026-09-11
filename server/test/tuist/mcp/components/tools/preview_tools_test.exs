defmodule Tuist.MCP.Components.Tools.PreviewToolsTest do
  use ExUnit.Case, async: true

  alias Tuist.MCP.Components.Tools.PreviewSerializer

  test "rejects an unsupported platform instead of removing the filter" do
    assert {:error, "supported_platforms contains an unsupported platform."} =
             PreviewSerializer.cast_supported_platforms(["not-a-platform"])
  end
end
