defmodule Atlas.MCP.Tools.SetSignalSourceEnabled do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "set_signal_source_enabled",
    schema: Atlas.MCP.Automation.schema(:set_signal_source_enabled),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Enable or pause your signal source. Pausing prevents new admissions and pending decisions, without revoking existing history."

  def execute(conn, args), do: Automation.execute(:set_signal_source_enabled, conn, args)
end
