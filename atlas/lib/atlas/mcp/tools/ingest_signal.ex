defmodule Atlas.MCP.Tools.IngestSignal do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "ingest_signal",
    schema: Atlas.MCP.Automation.schema(:ingest_signal),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Submit provider-neutral evidence to your enabled signal source. Envelope is capped at 12000 JSON bytes. External IDs deduplicate exact retries; correlation keys group distinct events. Supply only evidence authorized for every configured source reader, never credentials."

  def execute(conn, args), do: Automation.execute(:ingest_signal, conn, args)
end
