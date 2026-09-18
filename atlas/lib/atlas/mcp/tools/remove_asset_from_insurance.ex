defmodule Atlas.MCP.Tools.RemoveAssetFromInsurance do
  use Atlas.MCP.Tool,
    name: "remove_asset_from_insurance",
    schema: %{
      "type" => "object",
      "required" => ["member_id"],
      "properties" => %{
        "member_id" => %{"type" => "string"},
        "covered_to" => %{"type" => "string", "format" => "date"}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Insurance.member_schema()

  alias Atlas.Insurance.Policies
  alias Atlas.MCP.Serializers.Insurance, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Close a policy member on the given date (defaults to today). The membership stays as a historical record. Executive only."
  end

  def execute(conn, %{"member_id" => id} = args) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools"),
         %_{} = member <- Policies.get_member(id) do
      opts =
        case Map.get(args, "covered_to") do
          nil -> []
          value -> [covered_to: Date.from_iso8601!(value)]
        end

      case Policies.close_member(member, opts) do
        {:ok, updated} -> {:ok, Serializer.member(updated)}
        {:error, :already_closed} -> {:error, "Member is already closed."}
        {:error, changeset} -> {:error, "Could not close member: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Insurance policy member not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "member_id is required."}
end
