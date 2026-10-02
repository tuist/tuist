defmodule Atlas.MCP.Tools.MarkFinancingPaidOff do
  use Atlas.MCP.Tool,
    name: "mark_financing_paid_off",
    schema: %{
      "type" => "object",
      "required" => ["financing_id", "on"],
      "properties" => %{
        "financing_id" => %{"type" => "string"},
        "on" => %{"type" => "string", "format" => "date"}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Financings.financing_schema()

  alias Atlas.Finance.Financings
  alias Atlas.MCP.Serializers.Financings, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Transition a financing to paid_off. Loans: terminal. Leases: intermediate; option can still be exercised or the lease returned. Executive only."
  end

  def execute(conn, %{"financing_id" => id, "on" => on}) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Financing tools"),
         {:ok, date} <- Date.from_iso8601(on),
         %_{} = financing <- Financings.get(id) do
      case Financings.mark_paid_off(financing, date) do
        {:ok, updated} -> {:ok, Serializer.financing(updated)}
        {:error, changeset} -> {:error, "Could not mark paid_off: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      {:error, _} -> {:error, "on must be an ISO 8601 date."}
      nil -> {:error, "Financing not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "financing_id and on are required."}
end
