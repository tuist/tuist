defmodule Atlas.MCP.Tools.ListSpecs do
  @moduledoc "Lists visible specs, optionally filtered by status."

  use Atlas.MCP.Tool,
    name: "list_specs",
    schema: %{
      "type" => "object",
      "properties" => %{
        "status" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "specs" => %{"type" => "array", "items" => Atlas.MCP.Tools.SpecSerializers.spec_schema()}
      },
      "required" => ["specs"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Specs
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.SpecSerializers

  @impl EMCP.Tool
  def description, do: "List the specs visible to the caller."

  def execute(conn, args) do
    status = args["status"]

    specs =
      [user: Tool.current_user(conn)]
      |> Specs.list_specs()
      |> Enum.filter(fn spec -> is_nil(status) or Atom.to_string(spec.status) == status end)
      |> Enum.map(&SpecSerializers.spec/1)

    {:ok, %{"specs" => specs}}
  end
end
