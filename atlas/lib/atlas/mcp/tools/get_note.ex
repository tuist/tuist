defmodule Atlas.MCP.Tools.GetNote do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "get_note",
    schema: %{
      "type" => "object",
      "required" => ["note_id"],
      "properties" => %{"note_id" => %{"type" => "string", "description" => "Atlas note id."}}
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"note" => Atlas.MCP.Serializers.Notes.note_schema()},
      "required" => ["note"],
      "additionalProperties" => false
    }

  alias Atlas.MCP.Serializers.Notes, as: NoteSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Notes

  @impl EMCP.Tool
  def description, do: "Get a Markdown note by id."

  def execute(conn, %{"note_id" => note_id}) when is_binary(note_id) do
    with :ok <- Tool.authorize_authenticated(conn, "Note tools"),
         %{} = note <- Notes.get_note(note_id) do
      {:ok, %{note: NoteSerializer.note(note)}}
    else
      nil -> {:error, "Note not found."}
      {:error, reason} -> {:error, reason}
    end
  end

  def execute(_conn, _args), do: {:error, "note_id is required."}
end
