defmodule Atlas.MCP.Tools.CreateManualFinanceInvoiceTest do
  use Atlas.MCP.ToolCase

  import Atlas.FinanceFixtures

  alias Atlas.Finance.Invoice
  alias Atlas.Finance.Transaction
  alias Atlas.MCP.Tools.CreateManualFinanceInvoice
  alias Atlas.MCP.Tools.DeleteManualFinanceInvoice
  alias Atlas.MCP.Tools.UpdateManualFinanceInvoice

  test "manual bookkeeping lifecycle enforces finance write and cannot overwrite imported provenance" do
    user = insert_user!(%{scopes: ["finance:write"]})
    reader = insert_user!(%{scopes: ["finance:read"]})
    conn = mcp_conn(user)

    attrs = %{
      "vendor_name" => "Manual vendor",
      "invoice_date" => "2027-01-15",
      "total_amount_value" => "35.45",
      "total_amount_currency" => "EUR",
      "metadata" => %{"source" => "forged"}
    }

    assert {:error, _reason} = execute_tool(CreateManualFinanceInvoice, mcp_conn(reader), attrs)

    assert {:ok, %{item: %{id: id, fields: %{status: "needs_review"}, can_edit: true}}} =
             execute_tool(CreateManualFinanceInvoice, conn, attrs)

    assert Repo.get!(Invoice, id).metadata == %{"source" => "manual", "created_by_id" => user.id}

    assert {:error, _reason} =
             execute_tool(UpdateManualFinanceInvoice, mcp_conn(reader), %{"invoice_id" => id, "vendor_name" => "Denied"})

    assert {:error, _reason} = execute_tool(DeleteManualFinanceInvoice, mcp_conn(reader), %{"invoice_id" => id})

    assert {:ok, %{item: %{fields: %{vendor_name: "Corrected vendor"}}}} =
             execute_tool(UpdateManualFinanceInvoice, conn, %{"invoice_id" => id, "vendor_name" => "Corrected vendor"})

    imported = insert_finance_invoice!(%{document_id: nil, metadata: %{}})
    source = insert_finance_source!()
    account = insert_finance_account!(source)
    transaction = insert_finance_transaction!(account)
    linked = insert_finance_invoice!(%{metadata: %{"source" => "manual"}, finance_transaction_id: transaction.id})

    for invoice <- [imported, linked] do
      assert {:error, _reason} =
               execute_tool(UpdateManualFinanceInvoice, conn, %{"invoice_id" => invoice.id, "vendor_name" => "Denied"})

      assert {:error, _reason} = execute_tool(DeleteManualFinanceInvoice, conn, %{"invoice_id" => invoice.id})
      assert Repo.get!(Invoice, invoice.id).vendor_name == invoice.vendor_name
    end

    for bad_amount <- ["invalid", "NaN", "Infinity", "1.235", "10000000000000.00"] do
      assert {:error, _reason} =
               execute_tool(CreateManualFinanceInvoice, conn, Map.put(attrs, "total_amount_value", bad_amount))
    end

    assert {:error, _reason} = execute_tool(UpdateManualFinanceInvoice, conn, %{"invoice_id" => "invalid"})
    assert {:ok, %{deleted: true}} = execute_tool(DeleteManualFinanceInvoice, conn, %{"invoice_id" => id})
    assert Repo.get(Invoice, id) == nil
    assert Repo.get!(Transaction, transaction.id).id == transaction.id
  end
end
