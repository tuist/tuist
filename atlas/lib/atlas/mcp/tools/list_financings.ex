defmodule Atlas.MCP.Tools.ListFinancings do
  use Atlas.MCP.Tool,
    name: "list_financings",
    schema: %{
      "type" => "object",
      "properties" => %{
        "query" => %{
          "type" => "string",
          "description" => "Search by provider, supplier, or reference."
        },
        "type" => %{"type" => "string", "enum" => Atlas.Finance.Financing.types()},
        "status" => %{"type" => "string", "enum" => Atlas.Finance.Financing.statuses()},
        "page" => %{"type" => "integer", "minimum" => 1},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 200}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Financings.financing_list_schema()

  alias Atlas.Finance.Financings
  alias Atlas.MCP.Serializers.Financings, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "List hardware financing arrangements. Executive only."
  end

  def execute(conn, args) when is_map(args) do
    with :ok <- Tool.authorize_executive(conn, "Financing tools") do
      filters =
        args
        |> Map.take(["type", "status"])
        |> Enum.map(fn {k, v} -> %{field: String.to_existing_atom(k), op: :==, value: v} end)

      {rows, _meta} =
        Financings.list(
          %{
            page: Map.get(args, "page", 1),
            page_size: Map.get(args, "page_size", 25),
            filters: filters
          },
          query: Map.get(args, "query")
        )

      {:ok, Serializer.financing_list(rows)}
    end
  end
end
