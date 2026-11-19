defmodule Atlas.MCP.Tools.ListSignals do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "list_signals",
    schema: Atlas.MCP.Automation.schema(:list_signals),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "List authorized signal receipts, ordered now/today/later/unclassified, then oldest first. Optional decision-status filter; twenty per page. Read evidence separately with get_signal."

  def execute(conn, args), do: Automation.execute(:list_signals, conn, args)
end
