defmodule Atlas.MCP.Tools.GetFinancing do
  use Atlas.MCP.Tool,
    name: "get_financing",
    schema: %{
      "type" => "object",
      "required" => ["financing_id"],
      "properties" => %{"financing_id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Financings.financing_schema()

  alias Atlas.Finance.Financings
  alias Atlas.MCP.Serializers.Financings, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Fetch a single hardware financing arrangement. Executive only."
  end

  def execute(conn, %{"financing_id" => id}) do
    with :ok <- Tool.authorize_executive(conn, "Financing tools") do
      case Financings.get(id) do
        nil -> {:error, "Financing not found."}
        financing -> {:ok, Serializer.financing(financing)}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "financing_id is required."}
end
