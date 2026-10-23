defmodule Atlas.MCP.Tools.UpdateAutomationWorkflow do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "update_automation_workflow",
    schema: Atlas.MCP.Automation.schema(:update_workflow),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Partially update an automation workflow draft. Does not mutate any published revision or rebind existing runs/triggers. Use save_automation_workflow with publish=true to save a ready new version."

  def execute(conn, args), do: Automation.execute(:update_workflow, conn, args)
end
