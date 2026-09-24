defmodule Atlas.MCP.Tools.AddSpecComment do
  @moduledoc "Adds a comment to a spec."

  use Atlas.MCP.Tool,
    name: "add_spec_comment",
    schema: %{
      "type" => "object",
      "required" => ["spec_id", "body"],
      "properties" => %{
        "spec_id" => %{
          "type" => "string",
          "description" => "Spec identifier, public number, or /engineering/specs/:number URL."
        },
        "body" => %{"type" => "string"},
        "author_name" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"spec" => Atlas.MCP.Tools.SpecSerializers.spec_schema()},
      "required" => ["spec"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Specs
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.SpecSerializers

  @impl EMCP.Tool
  def description, do: "Add a comment to a visible spec."

  def execute(conn, %{"spec_id" => spec_id} = args) do
    user = Tool.current_user(conn)

    case Specs.fetch_visible_spec_by_reference(spec_id, user) do
      {:ok, spec} ->
        case Specs.add_comment(spec, Map.take(args, ["body", "author_name"]), user) do
          {:ok, _comment} ->
            {:ok, %{"spec" => SpecSerializers.spec(Specs.get_spec!(spec.id))}}

          {:error, :unauthorized} ->
            {:error, "Only authenticated operators can comment on specs."}

          {:error, changeset} ->
            {:error, "Could not add comment: #{Tool.format_changeset_errors(changeset)}"}
        end

      {:error, :not_found} ->
        {:error, "Spec not found."}
    end
  end
end
