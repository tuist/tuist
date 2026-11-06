defmodule Atlas.MCP.Tools.CreateAutomationBehavior do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "create_automation_behavior",
    schema: Atlas.MCP.Automation.schema(:behavior),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Save a configured behavior with object contracts. javascript.evaluate requires configuration.source; JS computes JSON and cannot call host tools."

  def execute(conn, args), do: Automation.execute(:behavior, conn, args)
end
