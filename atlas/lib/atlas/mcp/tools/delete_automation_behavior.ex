defmodule Atlas.MCP.Tools.DeleteAutomationBehavior do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "delete_automation_behavior",
    schema: Atlas.MCP.Automation.schema(:delete_behavior),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Delete a creator-owned saved behavior configuration, not its trusted registered type. Published workflow snapshots remain executable. Drafts that reference this configuration ID must be updated before publishing. Only invoke when deletion is requested."

  def execute(conn, args), do: Automation.execute(:delete_behavior, conn, args)
end
