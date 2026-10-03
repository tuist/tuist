defmodule Atlas.MCP.Tools.MatchFinancingPayment do
  use Atlas.MCP.Tool,
    name: "match_financing_payment",
    schema: %{
      "type" => "object",
      "required" => ["financing_id", "finance_transaction_id"],
      "properties" => %{
        "financing_id" => %{"type" => "string"},
        "finance_transaction_id" => %{"type" => "string"},
        "schedule_id" => %{"type" => "string"},
        "resolution_status" => %{
          "type" => "string",
          "enum" => Atlas.Finance.FinancingPayment.resolution_statuses()
        },
        "principal_amount" => %{"type" => "string"},
        "interest_amount" => %{"type" => "string"},
        "rental_amount" => %{"type" => "string"},
        "fee_amount" => %{"type" => "string"},
        "tax_amount" => %{"type" => "string"},
        "option_amount" => %{"type" => "string"},
        "deposit_amount" => %{"type" => "string"},
        "unclassified_amount" => %{"type" => "string"},
        "notes" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "payment_id" => %{"type" => "string"},
        "financing_id" => %{"type" => "string"},
        "resolution_status" => %{"type" => "string"}
      },
      "required" => ["payment_id", "financing_id", "resolution_status"],
      "additionalProperties" => false
    }

  alias Atlas.Finance.Financings
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Match a Finance.Transaction to a financing arrangement with a decomposed settlement (principal/interest/rental/fee/tax/option/deposit/unclassified). Cross-currency payments stay :partial. Executive only."
  end

  def execute(conn, %{"financing_id" => id, "finance_transaction_id" => txn_id} = args) do
    with :ok <- Tool.authorize_scope(conn, "assets:write", "Financing tools"),
         %_{} = financing <- Financings.get(id) do
      decomposition = args |> Map.drop(["financing_id", "finance_transaction_id"]) |> normalize()

      case Financings.match_payment(financing, txn_id, decomposition) do
        {:ok, payment} ->
          {:ok,
           %{
             payment_id: payment.id,
             financing_id: payment.financing_id,
             resolution_status: payment.resolution_status
           }}

        {:error, changeset} ->
          {:error, "Could not match payment: #{Tool.format_changeset_errors(changeset)}"}
      end
    else
      nil -> {:error, "Financing not found."}
    end
  end

  def execute(_conn, _args), do: {:error, "financing_id and finance_transaction_id are required."}

  defp normalize(attrs) do
    attrs
    |> Map.new(fn
      {"resolution_status", v} -> {:resolution_status, v}
      {"schedule_id", v} -> {:schedule_id, v}
      {"notes", v} -> {:notes, v}
      {k, v} when is_binary(v) -> {String.to_existing_atom(k), Decimal.new(v)}
      {k, v} -> {String.to_existing_atom(k), v}
    end)
  end
end
