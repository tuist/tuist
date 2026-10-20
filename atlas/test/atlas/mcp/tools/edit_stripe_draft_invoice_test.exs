defmodule Atlas.MCP.Tools.EditStripeDraftInvoiceTest do
  use Atlas.MCP.ToolCase, async: true

  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage
  alias Atlas.MCP.Tools.EditStripeDraftInvoice
  alias Atlas.Stripe
  alias Atlas.TestSupport.StripeClient

  test "attaches line items from the latest signed order form to an existing draft invoice" do
    account =
      insert_account!(%{
        account_key: "customer:mcp-edit",
        name: "MCP Edit Customer",
        currency: "EUR",
        stripe_customer_id: "cus_mcp_edit"
      })

    document =
      insert_order_form!(account, %{
        attributes: %{
          "signed" => true,
          "total" => "1500.00",
          "currency" => "EUR",
          "seats" => "15",
          "start_date" => "2026-06-01",
          "end_date" => "2027-05-31"
        }
      })

    StripeClient.put_add_invoice_items(fn {invoice_id, line_items, _opts} ->
      assert invoice_id == "in_existing_draft"

      assert [
               %{
                 amount_cents: 150_000,
                 currency: "EUR",
                 quantity: 15,
                 description: "Tuist Enterprise - 15 seats - 2026-06-01 to 2027-05-31"
               }
             ] = line_items

      {:ok,
       %Stripe.Invoice{
         id: "in_existing_draft",
         status: "draft",
         amount_value: Decimal.new("1500.00"),
         amount_currency: "EUR",
         dashboard_url: "https://dashboard.stripe.com/test/invoices/in_existing_draft",
         customer_id: "cus_mcp_edit"
       }}
    end)

    assert {:ok, payload} =
             execute_tool(EditStripeDraftInvoice, executive_mcp_conn(), %{
               "account_id" => account.id,
               "stripe_invoice_id" => "in_existing_draft"
             })

    assert payload.account.name == "MCP Edit Customer"
    assert payload.source_document.id == document.id
    assert payload.draft_invoice.external_id == "in_existing_draft"
    assert payload.stripe_invoice.dashboard_url == "https://dashboard.stripe.com/test/invoices/in_existing_draft"
    assert [%{amount_currency: "EUR", quantity: 15}] = payload.line_items
    assert payload.updated_invoice_fields == []
  end

  test "updates description, due date, and metadata without re-attaching line items" do
    account =
      insert_account!(%{
        account_key: "customer:mcp-fields",
        name: "MCP Fields Only",
        currency: "USD",
        stripe_customer_id: "cus_mcp_fields"
      })

    test_pid = self()

    StripeClient.put_update_invoice(fn {invoice_id, attrs, _opts} ->
      send(test_pid, {:update, invoice_id, attrs})

      {:ok,
       %Stripe.Invoice{
         id: invoice_id,
         status: "draft",
         amount_value: Decimal.new("2500.00"),
         amount_currency: "USD",
         dashboard_url: "https://dashboard.stripe.com/test/invoices/#{invoice_id}",
         customer_id: "cus_mcp_fields"
       }}
    end)

    StripeClient.put_get_invoice(fn {invoice_id, _opts} ->
      {:ok,
       %Stripe.Invoice{
         id: invoice_id,
         status: "draft",
         amount_value: Decimal.new("2500.00"),
         amount_currency: "USD",
         dashboard_url: "https://dashboard.stripe.com/test/invoices/#{invoice_id}",
         customer_id: "cus_mcp_fields"
       }}
    end)

    assert {:ok, payload} =
             execute_tool(EditStripeDraftInvoice, executive_mcp_conn(), %{
               "account_id" => account.id,
               "stripe_invoice_id" => "in_fields_only",
               "description" => "Annual subscription",
               "days_until_due" => 45,
               "metadata" => %{"po_number" => "PO-789"},
               "attach_order_form_line_items" => false
             })

    assert payload.source_document == nil
    assert payload.line_items == []
    assert Enum.sort(payload.updated_invoice_fields) == ["days_until_due", "description", "metadata"]

    assert_received {:update, "in_fields_only",
                     %{description: "Annual subscription", days_until_due: 45, metadata: %{"po_number" => "PO-789"}}}
  end

  test "requires a stripe_invoice_id" do
    account = insert_account!(%{name: "Needs Id", stripe_customer_id: "cus_needs_id"})

    assert {:error, message} =
             execute_tool(EditStripeDraftInvoice, executive_mcp_conn(), %{"account_id" => account.id})

    assert message =~ "stripe_invoice_id is required"
  end

  test "attaches caller-supplied line items and skips the order-form lookup" do
    account =
      insert_account!(%{
        account_key: "customer:mcp-edit-override",
        name: "MCP Edit Override",
        currency: "USD",
        stripe_customer_id: "cus_mcp_edit_override"
      })

    StripeClient.put_add_invoice_items(fn {invoice_id, line_items, _opts} ->
      assert invoice_id == "in_edit_override_mcp"

      assert [
               %{
                 amount_cents: 1_620_000,
                 currency: "USD",
                 description: "Tuist SaaS (up to 30 devs)",
                 quantity: 30
               }
             ] = line_items

      {:ok,
       %Stripe.Invoice{
         id: "in_edit_override_mcp",
         status: "draft",
         amount_value: Decimal.new("16200.00"),
         amount_currency: "USD",
         dashboard_url: "https://dashboard.stripe.com/test/invoices/in_edit_override_mcp",
         customer_id: "cus_mcp_edit_override"
       }}
    end)

    assert {:ok, payload} =
             execute_tool(EditStripeDraftInvoice, executive_mcp_conn(), %{
               "account_id" => account.id,
               "stripe_invoice_id" => "in_edit_override_mcp",
               "line_items" => [
                 %{
                   "description" => "Tuist SaaS (up to 30 devs)",
                   "amount" => "16200",
                   "currency" => "USD",
                   "quantity" => 30
                 }
               ]
             })

    assert payload.source_document == nil
    assert [%{description: "Tuist SaaS (up to 30 devs)", amount_value: "16200"}] = payload.line_items
  end

  test "surfaces the Stripe error when line item attachment fails" do
    account =
      insert_account!(%{
        account_key: "customer:mcp-mismatch",
        name: "MCP Mismatch",
        currency: "USD",
        stripe_customer_id: "cus_mcp_mismatch"
      })

    insert_order_form!(account, %{
      attributes: %{
        "signed" => true,
        "total" => "500.00",
        "currency" => "USD"
      }
    })

    StripeClient.put_add_invoice_items(fn {_invoice_id, _line_items, _opts} ->
      {:error, {:invoice_item, "in_bad", {:http, 400}}}
    end)

    assert {:error, message} =
             execute_tool(EditStripeDraftInvoice, executive_mcp_conn(), %{
               "account_id" => account.id,
               "stripe_invoice_id" => "in_bad"
             })

    assert message =~ "could not attach"
    assert message =~ "in_bad"
  end

  defp insert_order_form!(account, attrs) do
    document_type = Documents.upsert_document_type("order_form")

    defaults = %{
      title: "Signed Order Form",
      original_filename: "signed-order-form.txt",
      content_type: "text/plain",
      byte_size: 10,
      checksum_sha256: "#{System.unique_integer([:positive])}",
      storage_bucket: "test-documents",
      storage_key: "documents/#{System.unique_integer([:positive])}.txt",
      status: "ready",
      source: "upload",
      account_id: account.id,
      document_type_id: document_type.id
    }

    {foreign_keys, cast_attrs} =
      defaults
      |> Map.merge(attrs)
      |> Map.split([:account_id, :document_type_id, :correspondent_id, :uploaded_by_id])

    document =
      %Document{}
      |> Document.changeset(cast_attrs)
      |> Ecto.Changeset.change(foreign_keys)
      |> Repo.insert!()

    %DocumentPage{}
    |> DocumentPage.changeset(%{
      document_id: document.id,
      page_number: 1,
      content: "SIGNED ORDER FORM"
    })
    |> Repo.insert!()

    document
  end
end
