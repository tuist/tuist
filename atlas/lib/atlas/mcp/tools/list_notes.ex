defmodule Atlas.MCP.Tools.ListNotes do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "list_notes",
    schema: %{
      "type" => "object",
      "properties" => %{
        "query" => %{"type" => "string", "description" => "Filter note titles and Markdown content."},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema: Atlas.MCP.Serializers.Notes.list_response_schema()

  alias Atlas.MCP.Serializers.Notes, as: NoteSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Notes

  @impl EMCP.Tool
  def description, do: "List Markdown notes visible to the authenticated user."

  def execute(conn, args) do
    with :ok <- Tool.authorize_authenticated(conn, "Note tools") do
      notes =
        Notes.list_notes(
          limit: Tool.page_size(args),
          query: present(args["query"])
        )
        |> Enum.map(&NoteSerializer.note/1)

      {:ok, %{notes: notes, count: length(notes)}}
    end
  end

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp present(_value), do: nil
end
