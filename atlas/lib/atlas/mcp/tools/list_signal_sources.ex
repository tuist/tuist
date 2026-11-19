defmodule Atlas.MCP.Tools.ListSignalSources do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "list_signal_sources",
    schema: Atlas.MCP.Automation.schema(:list_signal_sources),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description, do: "List your portable signal source configurations, twenty per page."
  def execute(conn, args), do: Automation.execute(:list_signal_sources, conn, args)
end
