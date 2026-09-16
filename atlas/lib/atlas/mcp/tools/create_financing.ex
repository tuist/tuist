defmodule Atlas.MCP.Tools.CreateFinancing do
  use Atlas.MCP.Tool,
    name: "create_financing",
    schema: %{
      "type" => "object",
      "required" => ["type", "provider", "disbursement_or_commencement_on", "currency"],
      "properties" => %{
        "type" => %{"type" => "string", "enum" => Atlas.Finance.Financing.types()},
        "accounting_treatment" => %{
          "type" => "string",
          "enum" => Atlas.Finance.Financing.accounting_treatments()
        },
        "provider" => %{"type" => "string"},
        "supplier" => %{"type" => "string"},
        "reference" => %{"type" => "string"},
        "disbursement_or_commencement_on" => %{"type" => "string", "format" => "date"},
        "term_months" => %{"type" => "integer", "minimum" => 1},
        "currency" => %{"type" => "string"},
        "undiscounted_commitment" => %{"type" => "string"},
        "initial_liability" => %{"type" => "string"},
        "interest_rate" => %{"type" => "string"},
        "principal_amount" => %{"type" => "string"},
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
    "Register a new hardware financing arrangement (loan or lease). Executive only."
  end

  def execute(conn, args) when is_map(args) do
    with :ok <- Tool.authorize_executive(conn, "Financing tools") do
      case Financings.create(args) do
        {:ok, financing} -> {:ok, Serializer.financing(financing)}
        {:error, changeset} -> {:error, "Could not create financing: #{Tool.format_changeset_errors(changeset)}"}
      end
    end
  end
end
