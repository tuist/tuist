defmodule Atlas.MCP.Tools.CreateSignalSource do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "create_signal_source",
    schema: Atlas.MCP.Automation.schema(:create_signal_source),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Create a disabled portable signal source, pinning its workflow revision, execution owner, reader ceiling and domain scopes. Choose optional event_receiver OR polling. Polling watches a query on your personally connected Gmail or Slack account; explicitly confirm sharing matching excerpts with reader_ids. Gmail first requires separate read-only consent at /settings/connections. Polls start at source creation, not historical inbox scanning. Event receivers return callback/signing credentials once; treat them as secrets. Upstream subscription enrollment is separate. Bindings, including the provider identity, are immutable; create a new source to change them."

  def execute(conn, args), do: Automation.execute(:create_signal_source, conn, args)
end
