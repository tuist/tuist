defmodule Atlas.MCP.Tools.EditFinancingMetadata do
  use Atlas.MCP.Tool,
    name: "edit_financing_metadata",
    schema: %{
      "type" => "object",
      "required" => ["financing_id"],
      "properties" => %{
        "financing_id" => %{"type" => "string"},
        "provider" => %{"type" => "string"},
        "supplier" => %{"type" => "string"},
        "reference" => %{"type" => "string"},
        "disbursement_or_commencement_on" => %{"type" => "string", "format" => "date"},
        "term_months" => %{"type" => "integer", "minimum" => 1},
        "interest_rate" => %{"type" => "string"},
        "undiscounted_commitment" => %{"type" => "string"},
        "initial_liability" => %{"type" => "string"},
        "purchase_option_amount" => %{"type" => "string"},
        "purchase_option_available_from" => %{"type" => "string", "format" => "date"},
        "notes" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Financings.financing_schema()

  alias Atlas.Finance.Financings
  alias Atlas.MCP.Serializers.Financings, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Edit non-lifecycle metadata on a financing arrangement. Executive only."
  end

  def execute(conn, %{"financing_id" => id} = args) do
    with :ok <- Tool.authorize_executive(conn, "Financing tools"),
         %_{} = financing <- Financings.get(id) do
      attrs = Map.delete(args, "financing_id")

      case Financings.edit_metadata(financing, attrs) do
        {:ok, updated} -> {:ok, Serializer.financing(updated)}
        {:error, changeset} -> {:error, "Could not edit financing: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Financing not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "financing_id is required."}
end
