defmodule Atlas.MCP.Tools.UpdateAutomationBehavior do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "update_automation_behavior",
    schema: Atlas.MCP.Automation.schema(:update_behavior),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Partially update a creator-owned saved behavior configuration and validate its contracts. Only future publication snapshots see the change; existing workflow revisions and executions retain their original configuration/contracts."

  def execute(conn, args), do: Automation.execute(:update_behavior, conn, args)
end
