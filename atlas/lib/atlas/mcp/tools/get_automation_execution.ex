defmodule Atlas.MCP.Tools.GetAutomationExecution do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "get_automation_execution",
    schema: Atlas.MCP.Automation.schema(:get_run),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do: "Inspect a durable execution, its pinned revision, step attempts, inputs, outputs, and sanitized failure."

  def execute(conn, args), do: Automation.execute(:get_run, conn, args)
end
