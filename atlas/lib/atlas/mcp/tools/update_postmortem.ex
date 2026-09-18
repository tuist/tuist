defmodule Atlas.MCP.Tools.UpdatePostmortem do
  @moduledoc "Updates a postmortem."

  use Atlas.MCP.Tool,
    name: "update_postmortem",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{
          "type" => "string",
          "description" => "Postmortem identifier, public number, or shared postmortem address."
        },
        "body" => %{"type" => "string", "description" => "Complete postmortem in Markdown."},
        "visibility" => %{"type" => "string", "enum" => ["public", "private"]},
        "domain_ids" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "description" => "Domain identifiers to associate with the postmortem."
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
  def description, do: "Update a postmortem. Authenticated operators only."

  def execute(conn, %{"id" => id} = args) do
    user = Tool.current_user(conn)

    case Postmortems.fetch_visible_postmortem_by_reference(id, user) do
      {:ok, postmortem} -> update(postmortem, user, args)
      {:error, :not_found} -> {:error, "Postmortem not found."}
    end
  end

  defp update(postmortem, user, args) do
    attrs = Map.take(args, ["body", "visibility", "domain_ids"])

    case Postmortems.update_postmortem(postmortem, attrs, user) do
      {:ok, postmortem} ->
        postmortem = Postmortems.get_postmortem!(postmortem.id)
        {:ok, %{"postmortem" => PostmortemSerializers.postmortem(postmortem)}}

      {:error, :unauthorized} ->
        {:error, "Only authenticated operators can update postmortems."}

      {:error, changeset} ->
        {:error, "Could not update postmortem: #{Tool.format_changeset_errors(changeset)}"}
    end
  end
end
