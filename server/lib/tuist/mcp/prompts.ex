defmodule Tuist.MCP.Prompts do
  @moduledoc false

  alias Tuist.MCP.Prompts.FixFlakyTest

  @prompts [FixFlakyTest]

  @prompt_map Map.new(@prompts, fn mod -> {mod.name(), mod} end)

  def list do
    Enum.map(@prompts, & &1.definition())
  end

  def get(name, arguments) do
    case Map.fetch(@prompt_map, name) do
      {:ok, mod} -> mod.get(arguments)
      :error -> {:error, -32_602, "Unknown prompt: #{name}"}
    end
  end
end
