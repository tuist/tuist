defmodule Atlas.MCP.Tools.SearchNotes do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "search_notes",
    schema: %{
      "type" => "object",
      "required" => ["query"],
      "properties" => %{
        "query" => %{"type" => "string", "description" => "Natural-language search query."},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "results" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "note" => Atlas.MCP.Serializers.Notes.note_schema(),
              "excerpt" => %{"type" => "string"},
              "score" => %{"type" => "number"}
            },
            "required" => ["note", "excerpt", "score"],
            "additionalProperties" => false
          }
        },
        "count" => %{"type" => "integer"}
      },
      "required" => ["results", "count"],
      "additionalProperties" => false
    }

  alias Atlas.MCP.Serializers.Notes, as: NoteSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Notes

  @impl EMCP.Tool
  def description,
    do: "Search Markdown notes with QMD-style hybrid lexical/vector retrieval and reciprocal-rank fusion."

  def execute(conn, %{"query" => query} = args) when is_binary(query) do
    with :ok <- Tool.authorize_authenticated(conn, "Note tools") do
      results =
        Notes.search(query, limit: Tool.page_size(args))
        |> Enum.map(fn %{note: note, excerpt: excerpt, score: score} ->
          %{note: NoteSerializer.note(note), excerpt: excerpt, score: score}
        end)

      {:ok, %{results: results, count: length(results)}}
    end
  end

  def execute(_conn, _args), do: {:error, "query is required."}
end
