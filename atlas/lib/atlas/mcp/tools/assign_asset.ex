defmodule Atlas.MCP.Tools.AssignAsset do
  use Atlas.MCP.Tool,
    name: "assign_asset",
    schema: %{
      "type" => "object",
      "required" => ["asset_id", "user_id", "on"],
      "properties" => %{
        "asset_id" => %{"type" => "string"},
        "user_id" => %{"type" => "string"},
        "on" => %{"type" => "string", "format" => "date"},
        "notes" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Assets.asset_schema()

  alias Atlas.Assets
  alias Atlas.MCP.Serializers.Assets, as: AssetsSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Repo
  alias Atlas.Users.User

  @impl EMCP.Tool
  def description do
    "Assign an in_storage or in_service (unassigned) asset to a user. Sets placed_in_service_on if not already set. Executive only."
  end

  def execute(conn, %{"asset_id" => asset_id, "user_id" => user_id, "on" => on} = args) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Hardware tools"),
         {:ok, date} <- parse_date(on),
         %_{} = asset <- Assets.get_asset(asset_id),
         %User{} = user <- Repo.get(User, user_id) do
      case Assets.assign(asset, user, on: date, notes: Map.get(args, "notes")) do
        {:ok, updated} -> {:ok, AssetsSerializer.asset(updated)}
        {:error, changeset} -> {:error, "Could not assign asset: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      {:error, :invalid_date} -> {:error, "on must be an ISO 8601 date."}
      nil -> {:error, "Asset or user not found."}
      other -> other
    end
  end

  def execute(_conn, _args), do: {:error, "asset_id, user_id, and on are required."}

  defp parse_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, :invalid_date}
    end
  end
end
