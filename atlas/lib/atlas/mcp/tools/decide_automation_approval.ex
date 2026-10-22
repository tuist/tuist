defmodule Atlas.MCP.Tools.DecideAutomationApproval do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "decide_automation_approval",
    schema: Atlas.MCP.Automation.schema(:decide),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Approve the exact persisted payload or reject a pending gate. Only the assigned reviewer may decide; invoke only on explicit reviewer instruction."

  def execute(conn, args), do: Automation.execute(:decide, conn, args)
end
