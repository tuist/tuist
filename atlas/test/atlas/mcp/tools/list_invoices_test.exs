defmodule Atlas.MCP.Tools.ListInvoicesTest do
  use Atlas.MCP.ToolCase, async: true

  alias Atlas.MCP.Tools.ListInvoices

  test "returns Stripe invoices across accounts with linked account fields" do
    first =
      insert_account!(%{
        account_key: "global-invoices-first",
        name: "First Customer",
        stripe_customer_id: "cus_first"
      })

    second =
      insert_account!(%{
        account_key: "global-invoices-second",
        name: "Second Customer",
        stripe_customer_id: "cus_second"
      })

    insert_invoice!(first, %{
      external_id: "in_first",
      number: "TUIST-8001",
      due_date: ~D[2026-01-01],
      amount_value: Decimal.new("1200.50"),
      amount_currency: "EUR",
      status: "paid"
    })

    insert_invoice!(second, %{
      external_id: "in_second",
      number: "TUIST-8002",
      due_date: ~D[2026-03-01],
      amount_value: Decimal.new("30000.00"),
      amount_currency: "USD",
      status: "open"
    })

    {:ok, payload} = execute_tool(ListInvoices, nil, %{})

    assert payload.source == "stripe"
    assert payload.count == 2
    assert Enum.map(payload.invoices, & &1.external_id) == ["in_second", "in_first"]

    assert %{
             number: "TUIST-8002",
             due_date: "2026-03-01",
             amount_value: "30000.00",
             amount_currency: "USD",
             status: "open",
             account: %{
               account_key: "global-invoices-second",
               name: "Second Customer",
               stripe_customer_id: "cus_second"
             }
           } = hd(payload.invoices)
  end

  test "filters by source and status" do
    account = insert_account!(%{account_key: "global-invoices-filtered"})

    insert_invoice!(account, %{
      external_id: "in_open",
      source: "stripe",
      status: "open",
      due_date: ~D[2026-03-01]
    })

    insert_invoice!(account, %{external_id: "in_paid", source: "stripe", status: "paid"})

    insert_invoice!(account, %{
      external_id: "enterprise_invoice",
      source: "enterprise",
      status: "open",
      due_date: ~D[2026-01-01]
    })

    {:ok, open_stripe_payload} = execute_tool(ListInvoices, nil, %{"status" => "open"})
    {:ok, all_open_payload} = execute_tool(ListInvoices, nil, %{"source" => "all", "status" => "open"})

    assert Enum.map(open_stripe_payload.invoices, & &1.external_id) == ["in_open"]
    assert Enum.map(all_open_payload.invoices, & &1.external_id) == ["in_open", "enterprise_invoice"]
  end

  test "respects page_size" do
    account = insert_account!(%{account_key: "global-invoices-limit"})
    insert_invoice!(account, %{external_id: "in_first", due_date: ~D[2026-01-01]})
    insert_invoice!(account, %{external_id: "in_second", due_date: ~D[2026-02-01]})

    {:ok, payload} = execute_tool(ListInvoices, nil, %{"page_size" => 1})

    assert payload.count == 1
    assert [%{external_id: "in_second"}] = payload.invoices
  end
end
