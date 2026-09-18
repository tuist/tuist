defmodule Atlas.MCP.Tools.DeletePostmortem do
  @moduledoc "Deletes a postmortem and its action items."

  use Atlas.MCP.Tool,
    name: "delete_postmortem",
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
      "properties" => %{"deleted_postmortem" => Atlas.MCP.Tools.PostmortemSerializers.postmortem_schema()},
      "required" => ["deleted_postmortem"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Postmortems
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.PostmortemSerializers

  @impl EMCP.Tool
  def description, do: "Delete a postmortem and its action items. Authenticated operators only."

  def execute(conn, %{"id" => id}) do
    user = Tool.current_user(conn)

    if Postmortems.can_publish?(user) do
      delete(user, id)
    else
      {:error, "Only authenticated operators can delete postmortems."}
    end
  end

  defp delete(user, id) do
    case Postmortems.fetch_visible_postmortem_by_reference(id, user) do
      {:ok, postmortem} ->
        deleted = PostmortemSerializers.postmortem(postmortem)

        case Postmortems.delete_postmortem(postmortem, user) do
          {:ok, _postmortem} ->
            {:ok, %{"deleted_postmortem" => deleted}}

          {:error, :unauthorized} ->
            {:error, "Only authenticated operators can delete postmortems."}

          {:error, changeset} ->
            {:error, "Could not delete postmortem: #{Tool.format_changeset_errors(changeset)}"}
        end

      {:error, :not_found} ->
        {:error, "Postmortem not found."}
    end
  end
end
