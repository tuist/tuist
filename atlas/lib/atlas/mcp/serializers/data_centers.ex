defmodule Atlas.MCP.Serializers.DataCenters do
  @moduledoc false

  alias Atlas.Assets.DataCenter
  alias Atlas.MCP.Tool

  def data_center_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "provider" => %{"type" => ["string", "null"]},
        "city" => %{"type" => ["string", "null"]},
        "country" => %{"type" => ["string", "null"]},
        "status" => %{"type" => "string"},
        "notes" => %{"type" => ["string", "null"]},
        "data_center_url" => %{"type" => "string"}
      },
      "required" => ["id", "name", "status", "data_center_url"],
      "additionalProperties" => false
    }
  end

  def data_center(%DataCenter{} = dc) do
    %{
      id: dc.id,
      name: dc.name,
      provider: dc.provider,
      city: dc.city,
      country: dc.country,
      status: dc.status,
      notes: dc.notes,
      data_center_url: Tool.data_center_url(dc.id)
    }
  end

  def data_center_list_schema do
    %{
      "type" => "object",
      "properties" => %{
        "data_centers" => %{"type" => "array", "items" => data_center_schema()},
        "count" => %{"type" => "integer"}
      },
      "required" => ["data_centers", "count"],
      "additionalProperties" => false
    }
  end

  def data_center_list(rows) do
    %{data_centers: Enum.map(rows, &data_center/1), count: length(rows)}
  end
end
