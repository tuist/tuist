defmodule Atlas.MCP.Tools.GetSignalCandidates do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "get_signal_candidates",
    schema: Atlas.MCP.Automation.schema(:signal_candidates),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Explain up to three eligible routing matches for a signal: exact responsibility, then expertise, then configured role. Opt-in shared profiles only, bounded by source readership and current permissions. Does not invite anyone."

  def execute(conn, args), do: Automation.execute(:signal_candidates, conn, args)
end
