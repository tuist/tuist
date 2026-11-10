defmodule Atlas.MCP.Tools.DeleteAutomationWorkflow do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "delete_automation_workflow",
    schema: Atlas.MCP.Automation.schema(:delete_workflow),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Delete a creator-owned automation draft only if it has never had a published revision. Published workflows and their execution/approval history cannot be deleted through this interface. Only invoke when deletion is requested."

  def execute(conn, args), do: Automation.execute(:delete_workflow, conn, args)
end
