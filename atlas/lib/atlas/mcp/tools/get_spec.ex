defmodule Atlas.MCP.Tools.GetSpec do
  @moduledoc "Fetches a spec by identifier or public number."

  use Atlas.MCP.Tool,
    name: "get_spec",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{
          "type" => "string",
          "description" => "Spec identifier, public number, or /engineering/specs/:number URL."
        }
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
  def description, do: "Fetch a visible spec with its comments and revisions."

  def execute(conn, %{"id" => id}) do
    case Specs.fetch_visible_spec_by_reference(id, Tool.current_user(conn)) do
      {:ok, spec} ->
        {:ok, %{"spec" => SpecSerializers.spec(spec)}}

      {:error, :not_found} ->
        {:error, "Spec not found."}
    end
  end
end
