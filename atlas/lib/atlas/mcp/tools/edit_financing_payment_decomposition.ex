defmodule Atlas.MCP.Tools.EditFinancingPaymentDecomposition do
  use Atlas.MCP.Tool,
    name: "edit_financing_payment_decomposition",
    schema: %{
      "type" => "object",
      "required" => ["payment_id"],
      "properties" => %{
        "payment_id" => %{"type" => "string"},
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
        "resolution_status" => %{"type" => "string"}
      },
      "required" => ["payment_id", "resolution_status"],
      "additionalProperties" => false
    }

  alias Atlas.Finance.Financings
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Edit the decomposition of a matched financing payment. Serializes with concurrent exercise via a parent FOR UPDATE lock; pins option_amount when the financing is already :option_exercised. Executive only."
  end

  def execute(conn, %{"payment_id" => id} = args) do
    with :ok <- Tool.authorize_executive(conn, "Financing tools") do
      decomposition = args |> Map.delete("payment_id") |> normalize()

      case Financings.edit_payment_decomposition(id, decomposition) do
        {:ok, payment} ->
          {:ok, %{payment_id: payment.id, resolution_status: payment.resolution_status}}

        {:error, changeset} ->
          {:error, "Could not edit payment: #{Tool.format_changeset_errors(changeset)}"}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "payment_id is required."}

  defp normalize(attrs) do
    attrs
    |> Map.new(fn
      {"resolution_status", v} -> {:resolution_status, v}
      {"notes", v} -> {:notes, v}
      {k, v} when is_binary(v) -> {String.to_existing_atom(k), Decimal.new(v)}
      {k, v} -> {String.to_existing_atom(k), v}
    end)
  end
end
