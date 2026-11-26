defmodule Atlas.MCP.Tools.UpdateAccountInvoice do
  @moduledoc """
  Corrects an account invoice record that Atlas imported from outside Stripe.
  """

  use Atlas.MCP.Tool,
    name: "update_account_invoice",
    schema: %{
      "type" => "object",
      "required" => ["invoice_id"],
      "properties" => %{
        "invoice_id" => %{"type" => "string", "description" => "Atlas invoice id from list_invoices with source all."},
        "status" => %{
          "type" => "string",
          "description" => ~s{New status, for example "open", "paid", or "void".}
        },
        "number" => %{"type" => "string"},
        "due_date" => %{"type" => "string", "format" => "date"},
        "amount_value" => %{"type" => "string", "description" => ~s{Decimal amount, for example "16800.00".}},
        "amount_currency" => %{"type" => "string", "description" => ~s{ISO currency code, for example "EUR".}}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"invoice" => Atlas.MCP.Serializers.Accounts.invoice_schema()},
      "required" => ["invoice"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.Tool

  @fields ~w(status number due_date amount_value amount_currency)

  @impl EMCP.Tool
  def description,
    do:
      "Correct an account invoice record Atlas imported from outside Stripe, such as an enterprise wire invoice whose status, due date, or amount is out of date. Records synced from Stripe are refused; change those in Stripe or with mark_stripe_invoice_paid."

  def execute(conn, %{"invoice_id" => invoice_id} = args) do
    with :ok <- Tool.authorize_scope(conn, "finance:write", "Finance tools") do
      attrs = for {key, value} <- Map.take(args, @fields), into: %{}, do: {String.to_existing_atom(key), value}

      case Accounts.update_imported_invoice(invoice_id, attrs) do
        {:ok, invoice} -> {:ok, %{invoice: AccountSerializer.invoice(invoice)}}
        {:error, :not_found} -> {:error, "Account invoice not found: #{invoice_id}"}
        {:error, :stripe_synced} -> {:error, stripe_synced_message(invoice_id)}
        {:error, %Ecto.Changeset{} = changeset} -> {:error, "Invalid invoice: #{inspect(changeset.errors)}"}
      end
    end
  end

  def stripe_synced_message(invoice_id),
    do:
      "Account invoice #{invoice_id} is synced from Stripe and the next sync would overwrite the change; change it in Stripe instead."
end
