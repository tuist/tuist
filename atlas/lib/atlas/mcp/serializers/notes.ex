defmodule Atlas.MCP.Serializers.Notes do
  @moduledoc false

  alias Atlas.MCP.Tool
  alias Atlas.Notes.Note

  def note(%Note{} = note) do
    %{
      id: note.id,
      title: note.title,
      content: note.content,
      visibility: note.visibility,
      created_by: serialize_user(note.created_by),
      inserted_at: Tool.iso8601(note.inserted_at),
      updated_at: Tool.iso8601(note.updated_at),
      url: Tool.note_url(note.id)
    }
  end

  def note_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "content" => %{"type" => "string"},
        "visibility" => %{"type" => "string"},
        "created_by" =>
          Tool.nullable(%{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "name" => %{"type" => ["string", "null"]},
              "email" => %{"type" => "string"}
            },
            "required" => ["id", "name", "email"],
            "additionalProperties" => false
          }),
        "inserted_at" => %{"type" => ["string", "null"]},
        "updated_at" => %{"type" => ["string", "null"]},
        "url" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "title",
        "content",
        "visibility",
        "created_by",
        "inserted_at",
        "updated_at",
        "url"
      ],
      "additionalProperties" => false
    }
  end

  def list_response_schema do
    %{
      "type" => "object",
      "properties" => %{
        "notes" => %{"type" => "array", "items" => note_schema()},
        "count" => %{"type" => "integer"}
      },
      "required" => ["notes", "count"],
      "additionalProperties" => false
    }
  end

  defp serialize_user(nil), do: nil

  defp serialize_user(user) do
    %{id: user.id, name: user.name, email: user.email}
  end
end
