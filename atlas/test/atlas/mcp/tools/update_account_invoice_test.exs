defmodule Atlas.MCP.Tools.UpdateAccountInvoiceTest do
  use Atlas.MCP.ToolCase, async: true

  alias Atlas.Accounts.Invoice
  alias Atlas.MCP.Tools.DeleteAccountInvoice
  alias Atlas.MCP.Tools.UpdateAccountInvoice
  alias Atlas.Repo

  setup do
    account = insert_account!(%{account_key: "customer:imported-#{System.unique_integer([:positive])}"})

    imported =
      insert_invoice!(account, %{
        source: "enterprise",
        external_id: "stripe:in_imported_#{System.unique_integer([:positive])}",
        number: nil,
        due_date: ~D[2026-03-01],
        status: "open"
      })

    synced = insert_invoice!(account, %{status: "open"})
    %{imported: imported, synced: synced}
  end

  test "corrects an imported invoice and leaves its source and external id alone", %{imported: imported} do
    assert {:ok, %{invoice: invoice}} =
             execute_tool(UpdateAccountInvoice, executive_mcp_conn(), %{
               "invoice_id" => imported.id,
               "status" => "void",
               "number" => "TUIST-8992",
               "due_date" => "2026-04-11",
               "source" => "stripe",
               "external_id" => "in_other"
             })

    assert %{status: "void", number: "TUIST-8992", due_date: "2026-04-11"} = invoice

    stored = Repo.get!(Invoice, imported.id)
    assert {stored.source, stored.external_id} == {"enterprise", imported.external_id}
  end

  test "deletes an imported invoice", %{imported: imported} do
    assert {:ok, %{deleted: true}} =
             execute_tool(DeleteAccountInvoice, executive_mcp_conn(), %{"invoice_id" => imported.id})

    refute Repo.get(Invoice, imported.id)
  end

  test "refuses Stripe-synced invoices", %{synced: synced} do
    assert {:error, message} =
             execute_tool(UpdateAccountInvoice, executive_mcp_conn(), %{"invoice_id" => synced.id, "status" => "paid"})

    assert message =~ "synced from Stripe"

    assert {:error, _message} =
             execute_tool(DeleteAccountInvoice, executive_mcp_conn(), %{"invoice_id" => synced.id})

    assert Repo.get!(Invoice, synced.id).status == "open"
  end
end
