defmodule Atlas.MCP.Tools.ListAutomationTypes do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "list_automation_types",
    schema: Atlas.MCP.Automation.schema(:catalog),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Discover registered behavior types, plan syntax, JavaScript constraints, and every primitive's lifecycle. Includes the shared API/MCP operation inventory with full API paths, tool names and input/output schemas."

  def execute(conn, args), do: Automation.execute(:catalog, conn, args)
end
