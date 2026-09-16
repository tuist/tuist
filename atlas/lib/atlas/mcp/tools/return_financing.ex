defmodule Atlas.MCP.Tools.ReturnFinancing do
  use Atlas.MCP.Tool,
    name: "return_financing",
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
    "Return a leased financing arrangement. Transitions each linked asset to returned_to_lessor. Executive only."
  end

  def execute(conn, %{"financing_id" => id, "on" => on}) do
    with :ok <- Tool.authorize_executive(conn, "Financing tools"),
         {:ok, date} <- Date.from_iso8601(on),
         %_{} = financing <- Financings.get(id) do
      case Financings.return(financing, on: date) do
        {:ok, updated} -> {:ok, Serializer.financing(updated)}
        {:error, changeset} -> {:error, "Could not return financing: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      {:error, _} -> {:error, "on must be an ISO 8601 date."}
      nil -> {:error, "Financing not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "financing_id and on are required."}
end
