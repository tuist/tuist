defmodule Atlas.MCP.Tools.ControlAutomationExecution do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "control_automation_execution",
    schema: Atlas.MCP.Automation.schema(:control),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Cancel your nonterminal execution, or retry your failed execution from its failed step without repeating committed steps. No external side-effect actions are supported yet."

  def execute(conn, args), do: Automation.execute(:control, conn, args)
end
