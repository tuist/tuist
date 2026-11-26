defmodule Atlas.MCP.Tools.MarkStripeInvoicePaidTest do
  use Atlas.MCP.ToolCase, async: true

  alias Atlas.Accounts.Invoice
  alias Atlas.MCP.Tools.MarkStripeInvoicePaid
  alias Atlas.Repo
  alias Atlas.Stripe
  alias Atlas.TestSupport.StripeClient

  setup do
    suffix = System.unique_integer([:positive])

    account =
      insert_account!(%{
        account_key: "customer:mark-paid-#{suffix}",
        name: "Wire Customer",
        stripe_customer_id: "cus_wire_#{suffix}"
      })

    stored = insert_invoice!(account, %{external_id: "in_wire_#{suffix}", status: "open"})
    %{account: account, stored: stored}
  end

  defp stripe_invoice(account, stored, status) do
    %Stripe.Invoice{
      id: stored.external_id,
      number: stored.number,
      status: status,
      amount_value: Decimal.new("18000.00"),
      amount_currency: "USD",
      customer_id: account.stripe_customer_id,
      dashboard_url: "https://dashboard.stripe.com/invoices/#{stored.external_id}"
    }
  end

  test "pays an open invoice out of band and stores it as paid", %{account: account, stored: stored} do
    StripeClient.put_get_invoice({:ok, stripe_invoice(account, stored, "open")})

    StripeClient.put_pay_invoice_out_of_band(fn {invoice_id, _opts} ->
      assert invoice_id == stored.external_id
      {:ok, stripe_invoice(account, stored, "paid")}
    end)

    assert {:ok, payload} =
             execute_tool(MarkStripeInvoicePaid, executive_mcp_conn(), %{
               "account_id" => account.id,
               "stripe_invoice_id" => stored.external_id
             })

    assert payload.invoice.status == "paid"
    assert Repo.get!(Invoice, stored.id).status == "paid"
  end

  test "refuses another customer's invoice and invoices that are not open", %{account: account, stored: stored} do
    StripeClient.put_pay_invoice_out_of_band(fn _args -> flunk("must not pay") end)

    StripeClient.put_get_invoice({:ok, %{stripe_invoice(account, stored, "open") | customer_id: "cus_someone_else"}})

    assert {:error, message} =
             execute_tool(MarkStripeInvoicePaid, executive_mcp_conn(), %{
               "account_id" => account.id,
               "stripe_invoice_id" => stored.external_id
             })

    assert message =~ "does not belong"

    StripeClient.put_get_invoice({:ok, stripe_invoice(account, stored, "void")})

    assert {:error, message} =
             execute_tool(MarkStripeInvoicePaid, executive_mcp_conn(), %{
               "account_id" => account.id,
               "stripe_invoice_id" => stored.external_id
             })

    assert message =~ "is void"
    assert Repo.get!(Invoice, stored.id).status == "open"
  end
end
