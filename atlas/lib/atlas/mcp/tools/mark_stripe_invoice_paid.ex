defmodule Atlas.MCP.Tools.MarkStripeInvoicePaid do
  @moduledoc """
  Marks an account's open Stripe invoice as paid outside Stripe.
  """

  use Atlas.MCP.Tool,
    name: "mark_stripe_invoice_paid",
    schema: %{
      "type" => "object",
      "required" => ["stripe_invoice_id"],
      "properties" =>
        Map.put(
          Atlas.MCP.AccountLookup.identifier_schema_properties(),
          "stripe_invoice_id",
          %{"type" => "string", "description" => "Open Stripe invoice id, for example `in_1Abc...`."}
        )
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "invoice" => Atlas.MCP.Serializers.Accounts.invoice_schema(),
        "dashboard_url" => %{"type" => ["string", "null"]}
      },
      "required" => ["invoice", "dashboard_url"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description,
    do:
      "Mark an account's open Stripe invoice as paid outside Stripe (paid out of band), for example after the customer's bank wire arrived. Stripe charges nothing and stops reminders. Confirm the payment reached the bank first; this cannot be undone."

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "finance:write", "Finance tools"),
         {:ok, account} <- AccountLookup.resolve(args),
         {:ok, invoice_id} <- fetch_invoice_id(args) do
      case Accounts.mark_stripe_invoice_paid_out_of_band(account, invoice_id) do
        {:ok, %{invoice: invoice, stripe_invoice: stripe_invoice}} ->
          {:ok, %{invoice: AccountSerializer.invoice(invoice), dashboard_url: stripe_invoice.dashboard_url}}

        {:error, reason} ->
          {:error, error_message(reason, account, invoice_id)}
      end
    end
  end

  defp fetch_invoice_id(%{"stripe_invoice_id" => value}) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, "stripe_invoice_id is required."}
      trimmed -> {:ok, trimmed}
    end
  end

  defp fetch_invoice_id(_args), do: {:error, "stripe_invoice_id is required."}

  defp error_message(:invoice_not_for_account, account, invoice_id),
    do: "Stripe invoice #{invoice_id} does not belong to #{account.name}'s Stripe customer."

  defp error_message({:invoice_not_open, status}, _account, invoice_id),
    do: "Stripe invoice #{invoice_id} is #{status || "unknown"}; only open invoices can be marked paid."

  defp error_message(:stripe_disabled, _account, _invoice_id), do: "Stripe is not configured."

  defp error_message(reason, _account, invoice_id),
    do: "Could not mark Stripe invoice #{invoice_id} paid: #{inspect(reason)}"
end
