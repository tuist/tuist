defmodule Atlas.MCP.Tools.ListInsurancePolicies do
  use Atlas.MCP.Tool,
    name: "list_insurance_policies",
    schema: %{
      "type" => "object",
      "properties" => %{
        "status" => %{"type" => "string", "enum" => Atlas.Insurance.Policy.statuses()},
        "provider" => %{"type" => "string"},
        "page" => %{"type" => "integer", "minimum" => 1},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 200}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Insurance.policy_list_schema()

  alias Atlas.Insurance.Policies
  alias Atlas.MCP.Serializers.Insurance, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "List insurance policies. Executive only."
  end

  def execute(conn, args) when is_map(args) do
    with :ok <- Tool.authorize_scope(conn, "assets:read", "Hardware tools") do
      filters =
        args
        |> Map.take(["status", "provider"])
        |> Enum.map(fn {k, v} -> %{field: String.to_existing_atom(k), op: :==, value: v} end)

      {rows, _meta} =
        Policies.list(%{
          page: Map.get(args, "page", 1),
          page_size: Map.get(args, "page_size", 25),
          filters: filters
        })

      {:ok, Serializer.policy_list(rows)}
    end
  end
end
