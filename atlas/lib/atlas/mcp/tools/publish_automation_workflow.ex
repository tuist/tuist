defmodule Atlas.MCP.Tools.PublishAutomationWorkflow do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "publish_automation_workflow",
    schema: Atlas.MCP.Automation.schema(:publish),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Publish an immutable workflow revision with pinned behavior configurations. Requires explicit authorization to publish; does not alter existing trigger bindings."

  def execute(conn, args), do: Automation.execute(:publish, conn, args)
end
