defmodule Atlas.MCP.Tools.ListEmailAudiences do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "list_email_audiences",
    schema: %{"type" => "object", "properties" => %{}},
    output_schema:
      Atlas.MCP.Serializers.GTMEmail.list_schema(:audiences, Atlas.MCP.Serializers.GTMEmail.audience_schema())

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTMEmail

  @impl EMCP.Tool
  def description, do: "List Atlas email audiences with their subscriber and broadcast counts."

  def execute(_conn, _args) do
    {audiences, _metadata} = GTM.list_email_audiences()
    serialized = Enum.map(audiences, &GTMEmail.audience/1)
    {:ok, %{audiences: serialized, count: length(serialized)}}
  end
end
