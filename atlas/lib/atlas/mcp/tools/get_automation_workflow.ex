defmodule Atlas.MCP.Tools.GetAutomationWorkflow do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "get_automation_workflow",
    schema: Atlas.MCP.Automation.schema(:get_workflow),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description, do: "Read an automation workflow draft and its published revision ID."
  def execute(conn, args), do: Automation.execute(:get_workflow, conn, args)
end
