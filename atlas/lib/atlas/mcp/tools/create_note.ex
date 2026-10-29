defmodule Atlas.MCP.Tools.CreateNote do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "create_note",
    schema: %{
      "type" => "object",
      "required" => ["content"],
      "properties" => %{
        "content" => %{
          "type" => "string",
          "description" => "Markdown document. It must contain a level-one heading used as its title."
        },
        "visibility" => %{
          "type" => "string",
          "enum" => Atlas.Notes.Note.visibilities(),
          "default" => "authenticated"
        }
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
  def description, do: "Create an authenticated Markdown note in Atlas."

  def execute(conn, %{"content" => content} = args) when is_binary(content) do
    with :ok <- Tool.authorize_authenticated(conn, "Note tools"),
         {:ok, note} <- Notes.create_note(note_attrs(args), Tool.current_user(conn)) do
      {:ok, %{note: NoteSerializer.note(note)}}
    else
      {:error, :authentication_required} -> {:error, "Note tools require an authenticated user."}
      {:error, changeset} -> {:error, "Could not create note: #{Tool.format_changeset_errors(changeset)}"}
    end
  end

  def execute(_conn, _args), do: {:error, "content is required."}

  defp note_attrs(args), do: Map.take(args, ["content", "visibility"])
end
