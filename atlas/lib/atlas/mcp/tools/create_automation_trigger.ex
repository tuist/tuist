defmodule Atlas.MCP.Tools.CreateAutomationTrigger do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "create_automation_trigger",
    schema: Atlas.MCP.Automation.schema(:trigger),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Create an enabled UTC cron schedule or bearer-authenticated webhook bound to a published revision and caller identity. Only configure when requested. Webhook credentials are returned once."

  def execute(conn, args), do: Automation.execute(:trigger, conn, args)
end
