defmodule Atlas.MCP.Tools.AddAssetToInsurance do
  use Atlas.MCP.Tool,
    name: "add_asset_to_insurance",
    schema: %{
      "type" => "object",
      "required" => ["policy_id", "asset_id", "declared_value"],
      "properties" => %{
        "policy_id" => %{"type" => "string"},
        "asset_id" => %{"type" => "string"},
        "declared_value" => %{"type" => "string"},
        "covered_from" => %{"type" => "string", "format" => "date"},
        "notes" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Insurance.member_schema()

  alias Atlas.Insurance.Policies
  alias Atlas.MCP.Serializers.Insurance, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Declare an asset as covered under an insurance policy, with a declared value. Executive only."
  end

  def execute(conn, %{"policy_id" => policy_id, "asset_id" => asset_id, "declared_value" => value} = args) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools"),
         %_{} = policy <- Policies.get(policy_id) do
      attrs = %{
        asset_id: asset_id,
        declared_value: Decimal.new(value)
      }

      attrs =
        case Map.get(args, "covered_from") do
          nil -> attrs
          value -> Map.put(attrs, :covered_from, Date.from_iso8601!(value))
        end

      attrs =
        case Map.get(args, "notes") do
          nil -> attrs
          value -> Map.put(attrs, :notes, value)
        end

      case Policies.add_member(policy, attrs) do
        {:ok, member} -> {:ok, Serializer.member(member)}
        {:error, changeset} -> {:error, "Could not add asset: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Insurance policy not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "policy_id, asset_id, and declared_value are required."}
end
