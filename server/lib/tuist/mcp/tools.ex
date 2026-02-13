defmodule Tuist.MCP.Tools do
  @moduledoc false

  alias Tuist.MCP.Tools.GetTestCase
  alias Tuist.MCP.Tools.GetTestCaseRun
  alias Tuist.MCP.Tools.ListFlakyTests
  alias Tuist.MCP.Tools.ListProjects

  @tools [ListProjects, ListFlakyTests, GetTestCase, GetTestCaseRun]

  @tool_map Map.new(@tools, fn mod -> {mod.name(), mod} end)

  def list do
    Enum.map(@tools, & &1.definition())
  end

  def call(name, arguments, subject) do
    case Map.fetch(@tool_map, name) do
      {:ok, mod} -> mod.call(arguments, subject)
      :error -> {:error, -32_602, "Unknown tool: #{name}"}
    end
  end
end
