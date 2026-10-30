defmodule Atlas.MCP.Tools.GetSignal do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "get_signal",
    schema: Atlas.MCP.Automation.schema(:get_signal),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Read a signal's evidence and explainable routing decision. Requires explicit source readership and current domain scopes, independently of Automation access. Not a workflow behavior."

  def execute(conn, args), do: Automation.execute(:get_signal, conn, args)
end
