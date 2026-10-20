defmodule Atlas.MCP.Tools.RecordAssetNote do
  use Atlas.MCP.Tool,
    name: "record_asset_note",
    schema: %{
      "type" => "object",
      "required" => ["asset_id", "occurred_on", "notes"],
      "properties" => %{
        "asset_id" => %{"type" => "string"},
        "occurred_on" => %{"type" => "string", "format" => "date"},
        "notes" => %{"type" => "string"},
        "client_reference" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Assets.event_schema()

  alias Atlas.Assets
  alias Atlas.MCP.Serializers.Assets, as: AssetsSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Attach a free-form note to an asset's timeline. Idempotent when client_reference is provided. Executive only."
  end

  def execute(conn, %{"asset_id" => asset_id} = args) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Hardware tools"),
         %_{} = asset <- Assets.get_asset(asset_id) do
      attrs = normalize(args)

      case Assets.record_note(asset, attrs) do
        {:ok, event} -> {:ok, AssetsSerializer.event(event)}
        {:error, changeset} -> {:error, "Could not record note: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Asset not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "asset_id, occurred_on, and notes are required."}

  defp normalize(args) do
    args
    |> Enum.map(fn
      {"occurred_on", v} -> {:occurred_on, Date.from_iso8601!(v)}
      {"notes", v} -> {:notes, v}
      {"client_reference", v} -> {:client_reference, v}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end
end
