defmodule Atlas.MCP.Tools.ListAccountInvoicesTest do
  use Atlas.MCP.ToolCase, async: true

  alias Atlas.MCP.Tools.ListAccountInvoices

  test "returns Stripe invoices newest first with billing fields" do
    account =
      insert_account!(%{
        account_key: "stripe-invoices-acct",
        name: "Stripe Customer",
        stripe_customer_id: "cus_123"
      })

    insert_invoice!(account, %{
      external_id: "in_old",
      number: "TUIST-8001",
      due_date: ~D[2026-01-01],
      amount_value: Decimal.new("1200.50"),
      amount_currency: "usd",
      status: "paid",
      stripe_url: "https://stripe.example/invoices/in_old"
    })

    insert_invoice!(account, %{
      external_id: "in_new",
      number: "TUIST-8002",
      due_date: ~D[2026-03-01],
      amount_value: Decimal.new("30000.00"),
      amount_currency: "USD",
      status: "open",
      stripe_url: "https://stripe.example/invoices/in_new"
    })

    {:ok, payload} = execute_tool(ListAccountInvoices, nil, %{"account_id" => account.id})

    assert payload.account.stripe_customer_id == "cus_123"
    assert payload.source == "stripe"
    assert payload.count == 2
    assert Enum.map(payload.invoices, & &1.external_id) == ["in_new", "in_old"]

    assert %{
             number: "TUIST-8002",
             due_date: "2026-03-01",
             amount_value: "30000.00",
             amount_currency: "USD",
             status: "open",
             stripe_url: "https://stripe.example/invoices/in_new"
           } = hd(payload.invoices)
  end

  test "filters to Stripe invoices unless all sources are requested" do
    account = insert_account!(%{account_key: "mixed-invoices-acct"})
    insert_invoice!(account, %{external_id: "in_stripe", source: "stripe"})
    insert_invoice!(account, %{external_id: "manual_invoice", source: "manual"})

    {:ok, stripe_payload} = execute_tool(ListAccountInvoices, nil, %{"account_id" => account.id})
    {:ok, all_payload} = execute_tool(ListAccountInvoices, nil, %{"account_id" => account.id, "source" => "all"})

    assert Enum.map(stripe_payload.invoices, & &1.external_id) == ["in_stripe"]
    assert all_payload.count == 2
  end

  test "respects page_size" do
    account = insert_account!(%{account_key: "invoice-limit-acct"})
    insert_invoice!(account, %{external_id: "in_first", due_date: ~D[2026-01-01]})
    insert_invoice!(account, %{external_id: "in_second", due_date: ~D[2026-02-01]})

    {:ok, payload} =
      execute_tool(ListAccountInvoices, nil, %{"account_id" => account.id, "page_size" => 1})

    assert payload.count == 1
    assert [%{external_id: "in_second"}] = payload.invoices
  end

  test "returns an error when no identifier is provided" do
    assert {:error, "Provide one of account_id, account_key, or handle."} =
             execute_tool(ListAccountInvoices, nil, %{})
  end
end
