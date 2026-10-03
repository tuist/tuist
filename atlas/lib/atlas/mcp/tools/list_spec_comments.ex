defmodule Atlas.MCP.Tools.ListSpecComments do
  @moduledoc "Lists the comments on a visible spec."

  use Atlas.MCP.Tool,
    name: "list_spec_comments",
    schema: %{
      "type" => "object",
      "required" => ["spec_id"],
      "properties" => %{
        "spec_id" => %{
          "type" => "string",
          "description" => "Spec identifier, public number, or /engineering/specs/:number URL."
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "spec" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "string"},
            "number" => %{"type" => ["integer", "null"]},
            "title" => %{"type" => "string"}
          },
          "required" => ["id", "number", "title"],
          "additionalProperties" => false
        },
        "comments" => %{
          "type" => "array",
          "items" => Atlas.MCP.Tools.SpecSerializers.comment_schema()
        }
      },
      "required" => ["spec", "comments"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Specs
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.SpecSerializers

  @impl EMCP.Tool
  def description, do: "List comments for one visible spec."

  def execute(conn, %{"spec_id" => spec_id}) do
    case Specs.fetch_visible_spec_by_reference(spec_id, Tool.current_user(conn)) do
      {:ok, spec} ->
        {:ok,
         %{
           "spec" => %{"id" => spec.id, "number" => spec.number, "title" => spec.title},
           "comments" => SpecSerializers.comments(spec)
         }}

      {:error, :not_found} ->
        {:error, "Spec not found."}
    end
  end
end
