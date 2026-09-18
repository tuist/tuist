defmodule Atlas.MCP.Tools.ListPostmortems do
  @moduledoc "Lists visible postmortems."

  alias Atlas.MCP.Tools.PostmortemSerializers

  use Atlas.MCP.Tool,
    name: "list_postmortems",
    schema: %{"type" => "object", "properties" => %{}, "additionalProperties" => false},
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "postmortems" => %{
          "type" => "array",
          "items" => PostmortemSerializers.postmortem_schema()
        }
      },
      "required" => ["postmortems"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Postmortems
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "List the postmortems visible to the caller."

  def execute(conn, _args) do
    postmortems =
      conn
      |> Tool.current_user()
      |> Postmortems.list_postmortems()
      |> Enum.map(&PostmortemSerializers.postmortem/1)

    {:ok, %{"postmortems" => postmortems}}
  end
end
