defmodule Atlas.MCP.Tools.GetAutomationExecutionTrace do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "get_automation_execution_trace",
    schema: Atlas.MCP.Automation.schema(:trace),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Inspect correlated execution and step trace IDs, precise elapsed/worker/approval-wait timings, and a paginated structured event log (newest first, 20 per page). Includes sanitized worker exception types and stack frame locations, never exception messages, stack arguments, workflow source, inputs, outputs, or credentials. Historical executions may have no recorded timings or trace IDs."

  def execute(conn, args), do: Automation.execute(:trace, conn, args)
end
