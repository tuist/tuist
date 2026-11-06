defmodule Atlas.MCP.Tools.DeleteAutomationTrigger do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "delete_automation_trigger",
    schema: Atlas.MCP.Automation.schema(:delete_trigger),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Delete an execution-owner schedule or webhook, preventing future admissions and revoking its webhook credential. Already-admitted executions and their history remain intact. Only invoke when deletion is requested."

  def execute(conn, args), do: Automation.execute(:delete_trigger, conn, args)
end
