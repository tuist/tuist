defmodule Atlas.MCP.Tools.UpdateNote do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "update_note",
    schema: %{
      "type" => "object",
      "required" => ["note_id", "content"],
      "properties" => %{
        "note_id" => %{"type" => "string", "description" => "Atlas note id."},
        "content" => %{"type" => "string", "description" => "Updated Markdown document with an h1 heading."},
        "visibility" => %{"type" => "string", "enum" => Atlas.Notes.Note.visibilities()}
      }
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
  def description, do: "Update a Markdown note and recalculate its title and embedding."

  def execute(conn, %{"note_id" => note_id, "content" => content} = args)
      when is_binary(note_id) and is_binary(content) do
    with :ok <- Tool.authorize_authenticated(conn, "Note tools"),
         %{} = note <- Notes.get_note(note_id),
         {:ok, updated_note} <- Notes.update_note(note, Map.take(args, ["content", "visibility"])) do
      {:ok, %{note: NoteSerializer.note(updated_note)}}
    else
      nil -> {:error, "Note not found."}
      {:error, changeset} -> {:error, "Could not update note: #{Tool.format_changeset_errors(changeset)}"}
    end
  end

  def execute(_conn, _args), do: {:error, "note_id and content are required."}
end
