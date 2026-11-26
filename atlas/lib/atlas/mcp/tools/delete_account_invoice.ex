defmodule Atlas.MCP.Tools.DeleteAccountInvoice do
  @moduledoc """
  Deletes an account invoice record that Atlas imported from outside Stripe.
  """

  use Atlas.MCP.Tool,
    name: "delete_account_invoice",
    schema: %{
      "type" => "object",
      "required" => ["invoice_id"],
      "properties" => %{
        "invoice_id" => %{"type" => "string", "description" => "Atlas invoice id from list_invoices with source all."}
      }
    },
    output_schema: %{
      "type" => "object",
      "required" => ["deleted"],
      "properties" => %{"deleted" => %{"type" => "boolean"}},
      "additionalProperties" => false
    }

  alias Atlas.Accounts
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.UpdateAccountInvoice

  @impl EMCP.Tool
  def description,
    do:
      "Delete an account invoice record Atlas imported from outside Stripe, for example one whose invoice no longer exists. Records synced from Stripe are refused."

  def execute(conn, %{"invoice_id" => invoice_id}) do
    with :ok <- Tool.authorize_scope(conn, "finance:write", "Finance tools") do
      case Accounts.delete_imported_invoice(invoice_id) do
        {:ok, _invoice} -> {:ok, %{deleted: true}}
        {:error, :not_found} -> {:error, "Account invoice not found: #{invoice_id}"}
        {:error, :stripe_synced} -> {:error, UpdateAccountInvoice.stripe_synced_message(invoice_id)}
      end
    end
  end
end
