defmodule Atlas.MCP.Tools.SetFinancingAccountingTreatment do
  use Atlas.MCP.Tool,
    name: "set_financing_accounting_treatment",
    schema: %{
      "type" => "object",
      "required" => ["financing_id", "accounting_treatment"],
      "properties" => %{
        "financing_id" => %{"type" => "string"},
        "accounting_treatment" => %{
          "type" => "string",
          "enum" => Atlas.Finance.Financing.accounting_treatments()
        },
        "evidence" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Financings.financing_schema()

  alias Atlas.Finance.Financings
  alias Atlas.MCP.Serializers.Financings, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Set an accountant-approved accounting treatment on a financing arrangement, with a short evidence note. Executive only."
  end

  def execute(conn, %{"financing_id" => id, "accounting_treatment" => treatment} = args) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Financing tools"),
         %_{} = financing <- Financings.get(id) do
      case Financings.set_accounting_treatment(financing, treatment, Map.get(args, "evidence")) do
        {:ok, updated} -> {:ok, Serializer.financing(updated)}
        {:error, changeset} -> {:error, "Could not set treatment: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Financing not found."}
      other -> other
    end
  end

  def execute(_conn, _args), do: {:error, "financing_id and accounting_treatment are required."}
end
