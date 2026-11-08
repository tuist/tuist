defmodule Atlas.MCP.Tools.DecideSignal do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "decide_signal",
    schema: Atlas.MCP.Automation.schema(:decide_signal),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Apply a source-owner policy once: ignore or open a prioritized Orbit investigation with Pip and authorized business-profile matches. Exact replay is safe; changed decisions conflict. No outbound email or Slack send."

  def execute(conn, args), do: Automation.execute(:decide_signal, conn, args)
end
