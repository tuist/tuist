defmodule Atlas.MCP.Tools.UpdateAutomationTrigger do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "update_automation_trigger",
    schema: Atlas.MCP.Automation.schema(:update_trigger),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Update an execution-owner schedule/webhook name, enabled state, schedule input or UTC cron. Cron changes recompute the next occurrence. Kind, execution identity and pinned revision cannot change; create a replacement to rebind. Existing executions are unaffected."

  def execute(conn, args), do: Automation.execute(:update_trigger, conn, args)
end
