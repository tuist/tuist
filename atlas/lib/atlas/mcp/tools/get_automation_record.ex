defmodule Atlas.MCP.Tools.GetAutomationRecord do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "get_automation_record",
    schema: Atlas.MCP.Automation.schema(:get_record),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Inspect one automation primitive by kind and ID (registered type name for types). Includes saved configurations, immutable revisions, executions, attempts, events, approvals, schedules and webhooks. Reader-scoped; webhook credentials/hashes are never returned."

  def execute(conn, args), do: Automation.execute(:get_record, conn, args)
end
