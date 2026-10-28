defmodule Atlas.MCP.Tools.CreateStripeDraftInvoiceTest do
  use Atlas.MCP.ToolCase, async: true

  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage
  alias Atlas.MCP.Tools.CreateStripeDraftInvoice
  alias Atlas.Stripe
  alias Atlas.TestSupport.StripeClient

  test "creates a draft invoice and returns Slack-ready source links" do
    account =
      insert_account!(%{
        account_key: "customer:mcp-invoice",
        name: "MCP Invoice Customer",
        currency: "EUR",
        stripe_customer_id: "cus_mcp"
      })

    document =
      insert_order_form!(account, %{
        attributes: %{
          "signed" => true,
          "total" => "4200.00",
          "currency" => "EUR",
          "seats" => "21",
          "start_date" => "2026-06-01",
          "end_date" => "2027-05-31"
        }
      })

    StripeClient.put_create_draft_invoice(fn {customer_id, attrs, _opts} ->
      assert customer_id == "cus_mcp"

      assert [
               %{
                 amount_cents: 420_000,
                 description: "Tuist Enterprise - 21 seats - 2026-06-01 to 2027-05-31",
                 quantity: 21,
                 unit_amount_decimal: "20000"
               }
             ] = attrs.line_items

      {:ok,
       %Stripe.Invoice{
         id: "in_mcp",
         status: "draft",
         amount_value: Decimal.new("4200.00"),
         amount_currency: "EUR",
         dashboard_url: "https://dashboard.stripe.com/test/invoices/in_mcp",
         customer_id: "cus_mcp"
       }}
    end)

    assert {:ok, payload} = execute_tool(CreateStripeDraftInvoice, executive_mcp_conn(), %{"account_id" => account.id})

    assert payload.account.name == "MCP Invoice Customer"
    assert payload.source_document.id == document.id
    assert payload.source_document.url =~ "/documents/#{document.id}/download/signed-order-form.txt"
    assert payload.draft_invoice.external_id == "in_mcp"
    assert payload.draft_invoice.status == "draft"
    assert payload.stripe_invoice.dashboard_url == "https://dashboard.stripe.com/test/invoices/in_mcp"

    assert [
             %{
               description: "Tuist Enterprise - 21 seats - 2026-06-01 to 2027-05-31",
               amount_value: "4200.00",
               amount_currency: "EUR",
               quantity: 21,
               term_duration_days: "365"
             }
           ] = payload.line_items
  end

  test "returns the Stripe-disabled error when no API key is configured and the account has no customer id" do
    account = insert_account!(%{name: "No Stripe"})

    insert_order_form!(account, %{
      attributes: %{"signed" => true, "total" => "1000.00", "currency" => "USD"}
    })

    assert {:error, message} =
             execute_tool(CreateStripeDraftInvoice, executive_mcp_conn(), %{"account_id" => account.id})

    assert message =~ "Stripe is not configured"
  end

  test "surfaces the candidate names when multiple Stripe customers match" do
    account = insert_account!(%{name: "Acme Corp"})

    insert_order_form!(account, %{
      attributes: %{"signed" => true, "total" => "1000.00", "currency" => "USD"}
    })

    StripeClient.put_search_customers(fn {_query, _opts} ->
      {:ok,
       [
         %Stripe.Customer{id: "cus_a", name: "Acme Corp, Inc.", email: "ops@notion.so"},
         %Stripe.Customer{id: "cus_b", name: "Acme Corp"}
       ]}
    end)

    assert {:error, message} =
             execute_tool(CreateStripeDraftInvoice, executive_mcp_conn(), %{"account_id" => account.id})

    assert message =~ "Multiple Stripe customers"
    assert message =~ "Acme Corp, Inc."
    assert message =~ "cus_a"
    assert message =~ "cus_b"
  end

  test "creates the Stripe customer when none exists and persists it on the account" do
    account = insert_account!(%{name: "Greenfield Co", primary_domain: "greenfield.dev"})

    insert_order_form!(account, %{
      attributes: %{"signed" => true, "total" => "2400.00", "currency" => "EUR"}
    })

    test_pid = self()

    StripeClient.put_search_customers(fn {_query, _opts} -> {:ok, []} end)

    StripeClient.put_create_customer(fn {attrs, _opts} ->
      send(test_pid, {:created, attrs})

      {:ok,
       %Stripe.Customer{
         id: "cus_greenfield",
         name: attrs[:name],
         email: attrs[:email],
         dashboard_url: "https://dashboard.stripe.com/test/customers/cus_greenfield"
       }}
    end)

    StripeClient.put_create_draft_invoice(fn {customer_id, _attrs, _opts} ->
      assert customer_id == "cus_greenfield"

      {:ok,
       %Stripe.Invoice{
         id: "in_greenfield",
         status: "draft",
         amount_value: Decimal.new("2400.00"),
         amount_currency: "EUR",
         customer_id: "cus_greenfield",
         dashboard_url: "https://dashboard.stripe.com/test/invoices/in_greenfield"
       }}
    end)

    assert {:ok, payload} = execute_tool(CreateStripeDraftInvoice, executive_mcp_conn(), %{"account_id" => account.id})

    assert payload.stripe_customer.status == "created"
    assert payload.stripe_customer.id == "cus_greenfield"
    assert payload.account.stripe_customer_id == "cus_greenfield"
    assert_received {:created, attrs}
    assert attrs[:name] == "Greenfield Co"
    assert attrs[:metadata]["atlas_account_id"] == account.id
  end

  test "forwards caller-supplied line_items to the accounts module" do
    account =
      insert_account!(%{
        account_key: "customer:mcp-override",
        name: "MCP Override",
        currency: "USD",
        stripe_customer_id: "cus_mcp_override"
      })

    insert_order_form!(account, %{
      attributes: %{"signed" => true}
    })

    StripeClient.put_create_draft_invoice(fn {customer_id, attrs, _opts} ->
      assert customer_id == "cus_mcp_override"

      assert [
               %{
                 amount_cents: 1_620_000,
                 currency: "USD",
                 description: "Tuist SaaS (up to 30 devs)",
                 quantity: 30
               }
             ] = attrs.line_items

      {:ok,
       %Stripe.Invoice{
         id: "in_mcp_override",
         status: "draft",
         amount_value: Decimal.new("16200.00"),
         amount_currency: "USD",
         dashboard_url: "https://dashboard.stripe.com/test/invoices/in_mcp_override",
         customer_id: "cus_mcp_override"
       }}
    end)

    assert {:ok, payload} =
             execute_tool(CreateStripeDraftInvoice, executive_mcp_conn(), %{
               "account_id" => account.id,
               "line_items" => [
                 %{
                   "description" => "Tuist SaaS (up to 30 devs)",
                   "amount" => "16200.00",
                   "currency" => "USD",
                   "quantity" => 30
                 }
               ]
             })

    assert [%{description: "Tuist SaaS (up to 30 devs)", amount_value: "16200.00"}] =
             payload.line_items
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
      content: "SIGNED ORDER FORM\n\nTotal: EUR 4,200.00"
    })
    |> Repo.insert!()

    document
  end
end
