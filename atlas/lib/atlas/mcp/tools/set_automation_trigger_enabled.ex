defmodule Atlas.MCP.Tools.SetAutomationTriggerEnabled do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "set_automation_trigger_enabled",
    schema: Atlas.MCP.Automation.schema(:toggle),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do: "Pause or enable a schedule or webhook owned by the caller. Already-admitted executions are unaffected."

  def execute(conn, args), do: Automation.execute(:toggle, conn, args)
end
