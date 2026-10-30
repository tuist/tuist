defmodule Atlas.MCP.Tools.ValidateAutomationWorkflow do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "validate_automation_workflow",
    schema: Atlas.MCP.Automation.schema(:validate),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Compile and validate a workflow draft without executing its actions. JavaScript plan construction requires Linux isolation."

  def execute(conn, args), do: Automation.execute(:validate, conn, args)
end
