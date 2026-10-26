defmodule Atlas.MCP.Tools.ListAutomationRecords do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "list_automation_records",
    schema: Atlas.MCP.Automation.schema(:list),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "List any automation primitive with pagination: types, workflows, behaviors, revisions, executions, attempts, events, approvals, triggers, schedules or webhooks. Revisions require workflow_id; attempts/events require run_id. Execution history optionally accepts workflow_id, days (1–90), and end_date (ISO date, UTC); otherwise it is all-time. Webhook credentials/hashes are never returned."

  def execute(conn, args), do: Automation.execute(:list, conn, args)
end
