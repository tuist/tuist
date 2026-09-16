defmodule Atlas.MCP.Tools.EditInsuranceMember do
  use Atlas.MCP.Tool,
    name: "edit_insurance_member",
    schema: %{
      "type" => "object",
      "required" => ["member_id"],
      "properties" => %{
        "member_id" => %{"type" => "string"},
        "declared_value" => %{"type" => "string"},
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
    "Update the declared value or notes on an active insurance policy member. Executive only."
  end

  def execute(conn, %{"member_id" => id} = args) do
    with :ok <- Tool.authorize_executive(conn, "Hardware tools"),
         %_{} = member <- Policies.get_member(id) do
      attrs = args |> Map.delete("member_id") |> normalize()

      case Policies.edit_member(member, attrs) do
        {:ok, updated} -> {:ok, Serializer.member(updated)}
        {:error, changeset} -> {:error, "Could not edit member: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Insurance policy member not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "member_id is required."}

  defp normalize(attrs) do
    attrs
    |> Map.new(fn
      {"notes", v} -> {:notes, v}
      {"declared_value", v} -> {:declared_value, Decimal.new(v)}
      {k, v} -> {String.to_existing_atom(k), v}
    end)
  end
end
