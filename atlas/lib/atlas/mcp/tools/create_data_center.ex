defmodule Atlas.MCP.Tools.CreateDataCenter do
  use Atlas.MCP.Tool,
    name: "create_data_center",
    schema: %{
      "type" => "object",
      "required" => ["name"],
      "properties" => %{
        "name" => %{"type" => "string"},
        "provider" => %{"type" => "string"},
        "city" => %{"type" => "string"},
        "country" => %{"type" => "string"},
        "notes" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.DataCenters.data_center_schema()

  alias Atlas.Assets
  alias Atlas.MCP.Serializers.DataCenters, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Register a new hardware data center (colocation or private). Executive only."
  end

  def execute(conn, args) when is_map(args) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Hardware tools") do
      case Assets.create_data_center(args) do
        {:ok, dc} -> {:ok, Serializer.data_center(dc)}
        {:error, changeset} -> {:error, "Could not create data center: #{Tool.format_changeset_errors(changeset)}"}
      end
    end
  end
end
