defmodule Atlas.MCP.Tools.EditDataCenter do
  use Atlas.MCP.Tool,
    name: "edit_data_center",
    schema: %{
      "type" => "object",
      "required" => ["data_center_id"],
      "properties" => %{
        "data_center_id" => %{"type" => "string"},
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
    "Edit metadata on an existing data center. Executive only."
  end

  def execute(conn, %{"data_center_id" => id} = args) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools"),
         %_{} = dc <- Assets.get_data_center(id) do
      attrs = Map.delete(args, "data_center_id")

      case Assets.edit_data_center(dc, attrs) do
        {:ok, updated} -> {:ok, Serializer.data_center(updated)}
        {:error, changeset} -> {:error, "Could not edit data center: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Data center not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "data_center_id is required."}
end
