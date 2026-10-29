defmodule Atlas.MCP.Tools.GetPostmortem do
  @moduledoc "Fetches a postmortem by id or public number."

  use Atlas.MCP.Tool,
    name: "get_postmortem",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{
          "type" => "string",
          "description" => "Postmortem identifier, public number, or shared postmortem address."
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"postmortem" => Atlas.MCP.Tools.PostmortemSerializers.postmortem_schema()},
      "required" => ["postmortem"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Postmortems
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.PostmortemSerializers

  @impl EMCP.Tool
  def description, do: "Fetch one visible postmortem with its domains and action items."

  def execute(conn, %{"id" => id}) do
    case Postmortems.fetch_visible_postmortem_by_reference(id, Tool.current_user(conn)) do
      {:ok, postmortem} ->
        {:ok, %{"postmortem" => PostmortemSerializers.postmortem(postmortem)}}

      {:error, :not_found} ->
        {:error, "Postmortem not found."}
    end
  end
end
