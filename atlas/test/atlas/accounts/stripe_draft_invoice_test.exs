defmodule Atlas.Accounts.StripeDraftInvoiceTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Invoice
  alias Atlas.Audit.Activity
  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage
  alias Atlas.Repo
  alias Atlas.Stripe
  alias Atlas.TestSupport.StripeClient

  test "creates and persists a Stripe draft invoice from the latest signed order form" do
    account =
      insert_account!(%{
        account_key: "customer:acme",
        name: "Acme",
        currency: "USD",
        stripe_customer_id: "cus_acme"
      })

    _older =
      insert_order_form!(account, %{
        title: "Acme Signed Order Form 2025",
        document_date: ~D[2025-06-01],
        attributes: %{"signed" => true, "total" => "900.00", "currency" => "USD"}
      })

    latest =
      insert_order_form!(account, %{
        title: "Acme Signed Order Form 2026",
        document_date: ~D[2026-06-01],
        attributes: %{
          "signed" => true,
          "total" => "1,200.50",
          "currency" => "USD",
          "payment_terms" => "Net 45",
          "start_date" => "2026-06-01",
          "end_date" => "2027-05-31",
          "seats" => 25,
          "po_number" => "PO-123"
        }
      })

    _unsigned_newer =
      insert_order_form!(account, %{
        title: "Acme Draft Order Form 2027",
        document_date: ~D[2027-06-01],
        attributes: %{"total" => "2000.00", "currency" => "USD"}
      })

    StripeClient.put_create_draft_invoice(fn {customer_id, attrs, _opts} ->
      assert customer_id == "cus_acme"
      assert attrs.days_until_due == 45
      assert attrs.currency == "USD"
      assert is_binary(attrs.footer)
      assert attrs.metadata["atlas_account_id"] == account.id
      assert attrs.metadata["atlas_document_id"] == latest.id
      assert attrs.metadata["po_number"] == "PO-123"

      assert [
               %{
                 amount_cents: 120_050,
                 amount_value: amount,
                 currency: "USD",
                 description: "Tuist Enterprise - 25 seats - 2026-06-01 to 2027-05-31",
                 period_start: ~D[2026-06-01],
                 period_end: ~D[2027-05-31],
                 quantity: 25,
                 unit_amount_decimal: "4802",
                 metadata: %{
                   "product_name" => "Tuist Enterprise",
                   "seats" => "25",
                   "term_start" => "2026-06-01",
                   "term_end" => "2027-05-31",
                   "term_duration_days" => "365"
                 }
               }
             ] = attrs.line_items

      assert Decimal.equal?(amount, Decimal.new("1200.50"))

      {:ok,
       %Stripe.Invoice{
         id: "in_acme_draft",
         status: "draft",
         amount_value: Decimal.new("1200.50"),
         amount_currency: "USD",
         dashboard_url: "https://dashboard.stripe.com/test/invoices/in_acme_draft",
         customer_id: "cus_acme"
       }}
    end)

    assert {:ok, result} = Accounts.create_stripe_draft_invoice_from_latest_signed_order_form(account)

    assert result.source_document.id == latest.id
    assert result.days_until_due == 45

    assert [%{amount_cents: 120_050, description: "Tuist Enterprise - 25 seats - 2026-06-01 to 2027-05-31"}] =
             result.line_items

    assert %Invoice{} = stored = Repo.get_by!(Invoice, source: "stripe", external_id: "in_acme_draft")
    assert stored.account_id == account.id
    assert stored.status == "draft"
    assert stored.stripe_url == "https://dashboard.stripe.com/test/invoices/in_acme_draft"
    assert Decimal.equal?(stored.amount_value, Decimal.new("1200.50"))
    assert stored.amount_currency == "USD"

    activity = Repo.get_by!(Activity, action: "account_invoice.stripe_draft_created", target_id: stored.id)
    assert activity.metadata["source_document_id"] == latest.id
  end

  test "updates an existing Stripe customer missing billing profile from the signed order form" do
    account =
      insert_account!(%{
        account_key: "customer:safetyculture",
        name: "SafetyCulture",
        currency: "USD",
        stripe_customer_id: "cus_safetyculture"
      })

    document_type = Documents.upsert_document_type("order_form")

    latest =
      account
      |> insert_document!(%{
        title: "Order Form - SafetyCulture - Tuist Services",
        document_type_id: document_type.id,
        document_date: ~D[2026-06-24],
        attributes: %{
          "signed" => true,
          "total" => "18000.00",
          "currency" => "USD",
          "payment_terms" => "Net 30",
          "start_date" => "2026-07-01",
          "end_date" => "2027-06-30",
          "seats" => 30
        }
      })

    insert_page!(
      latest,
      """
      Order Details
      Sales Contact               Pedro Pinera
      Email                       pedro@tuist.dev

      Customer Details
      Bill Details
      Company                     SafetyCulture Pty Ltd
      Sold to Name                SafetyCulture Pty Ltd
      Bill to Name                SafetyCulture
      Email                       accounts@safetyculture.io
      Address                     72 Foveaux Street
      City                        Surry Hills
      ZIP/Postal Code             2010
      Country                     Australia

      Accepted and agreed to by the authorized representative of each Party.
      """
    )

    StripeClient.put_get_customer(fn {customer_id, _opts} ->
      assert customer_id == "cus_safetyculture"

      {:ok,
       %Stripe.Customer{
         id: "cus_safetyculture",
         name: "SafetyCulture",
         email: nil,
         address: nil
       }}
    end)

    StripeClient.put_update_customer(fn {customer_id, attrs, _opts} ->
      assert customer_id == "cus_safetyculture"

      assert attrs == %{
               email: "accounts@safetyculture.io",
               address: %{
                 line1: "72 Foveaux Street",
                 city: "Surry Hills",
                 postal_code: "2010",
                 country: "AU"
               }
             }

      {:ok,
       %Stripe.Customer{
         id: "cus_safetyculture",
         name: "SafetyCulture",
         email: "accounts@safetyculture.io",
         address: attrs.address
       }}
    end)

    StripeClient.put_create_draft_invoice(fn {customer_id, attrs, _opts} ->
      assert customer_id == "cus_safetyculture"
      assert attrs.currency == "USD"

      {:ok,
       %Stripe.Invoice{
         id: "in_safetyculture_draft",
         status: "draft",
         amount_value: Decimal.new("18000.00"),
         amount_currency: "USD",
         dashboard_url: "https://dashboard.stripe.com/test/invoices/in_safetyculture_draft",
         customer_id: "cus_safetyculture"
       }}
    end)

    assert {:ok, result} = Accounts.create_stripe_draft_invoice_from_latest_signed_order_form(account)

    assert result.source_document.id == latest.id
    assert result.stripe_customer.email == "accounts@safetyculture.io"
    assert result.stripe_customer.address.city == "Surry Hills"

    assert %Activity{} = activity = Repo.get_by(Activity, action: "stripe_customer.profile_updated")
    assert activity.target_id == "cus_safetyculture"
    assert activity.metadata["account_id"] == account.id
    assert "email" in activity.metadata["changed"]
    assert "address.line1" in activity.metadata["changed"]
  end

  test "creates a Stripe customer with the billing profile from the signed order form" do
    account =
      insert_account!(%{
        account_key: "customer:new-billing-email",
        name: "New Billing Email Customer",
        currency: "USD"
      })

    document_type = Documents.upsert_document_type("order_form")

    latest =
      account
      |> insert_document!(%{
        title: "Signed Order Form - New Billing Email Customer",
        document_type_id: document_type.id,
        document_date: ~D[2026-06-24],
        attributes: %{
          "signed" => true,
          "total" => "1200.00",
          "currency" => "USD"
        }
      })

    insert_page!(
      latest,
      """
      ORDER FORM

      Customer Details
      Bill Details
      Email billing@example.com
      Address 1 Market St
      City San Francisco
      ZIP/Postal Code 94105
      Country United States

      Accepted and agreed.
      """
    )

    StripeClient.put_search_customers(fn {query, _opts} ->
      assert query in [
               "name:'New Billing Email Customer'",
               "email:'billing@example.com'"
             ]

      {:ok, []}
    end)

    StripeClient.put_create_customer(fn {attrs, _opts} ->
      assert attrs[:email] == "billing@example.com"
      assert attrs[:address] == %{line1: "1 Market St", city: "San Francisco", postal_code: "94105", country: "US"}

      {:ok,
       %Stripe.Customer{
         id: "cus_new_billing_email",
         name: attrs[:name],
         email: attrs[:email],
         address: attrs[:address],
         dashboard_url: "https://dashboard.stripe.com/test/customers/cus_new_billing_email"
       }}
    end)

    StripeClient.put_create_draft_invoice(fn {customer_id, _attrs, _opts} ->
      assert customer_id == "cus_new_billing_email"

      {:ok,
       %Stripe.Invoice{
         id: "in_new_billing_email",
         status: "draft",
         amount_value: Decimal.new("1200.00"),
         amount_currency: "USD",
         dashboard_url: "https://dashboard.stripe.com/test/invoices/in_new_billing_email",
         customer_id: "cus_new_billing_email"
       }}
    end)

    assert {:ok, result} = Accounts.create_stripe_draft_invoice_from_latest_signed_order_form(account)

    assert result.source_document.id == latest.id
    assert result.stripe_customer_status == :created
    assert result.stripe_customer.email == "billing@example.com"
    assert result.stripe_customer.address.postal_code == "94105"
  end

  test "edit_stripe_draft_invoice attaches order-form line items to an existing draft invoice" do
    account =
      insert_account!(%{
        account_key: "customer:edit",
        name: "Edit Invoice Customer",
        currency: "USD",
        stripe_customer_id: "cus_edit"
      })

    signed =
      insert_order_form!(account, %{
        title: "Edit Signed Order Form",
        document_date: ~D[2026-06-01],
        attributes: %{
          "signed" => true,
          "total" => "3000.00",
          "currency" => "USD",
          "seats" => 30,
          "start_date" => "2026-06-01",
          "end_date" => "2027-05-31"
        }
      })

    StripeClient.put_add_invoice_items(fn {invoice_id, line_items, _opts} ->
      assert invoice_id == "in_existing_draft"
      assert [%{currency: "USD", amount_cents: 300_000, quantity: 30}] = line_items

      {:ok,
       %Stripe.Invoice{
         id: "in_existing_draft",
         status: "draft",
         amount_value: Decimal.new("3000.00"),
         amount_currency: "USD",
         dashboard_url: "https://dashboard.stripe.com/test/invoices/in_existing_draft",
         customer_id: "cus_edit"
       }}
    end)

    assert {:ok, result} = Accounts.edit_stripe_draft_invoice(account, "in_existing_draft")

    assert result.source_document.id == signed.id
    assert [%{amount_cents: 300_000}] = result.line_items
    assert result.updated_invoice_fields == []
    assert %Invoice{} = stored = Repo.get_by!(Invoice, source: "stripe", external_id: "in_existing_draft")
    assert stored.account_id == account.id
    assert stored.status == "draft"
  end

  test "edit_stripe_draft_invoice updates invoice fields and skips line items when asked" do
    account =
      insert_account!(%{
        account_key: "customer:edit-fields",
        name: "Edit Fields Only",
        currency: "USD",
        stripe_customer_id: "cus_edit_fields"
      })

    test_pid = self()

    StripeClient.put_update_invoice(fn {invoice_id, attrs, _opts} ->
      send(test_pid, {:update, invoice_id, attrs})

      {:ok,
       %Stripe.Invoice{
         id: invoice_id,
         status: "draft",
         amount_value: Decimal.new("1000.00"),
         amount_currency: "USD",
         dashboard_url: "https://dashboard.stripe.com/test/invoices/#{invoice_id}",
         customer_id: "cus_edit_fields"
       }}
    end)

    StripeClient.put_get_invoice(fn {invoice_id, _opts} ->
      send(test_pid, {:get, invoice_id})

      {:ok,
       %Stripe.Invoice{
         id: invoice_id,
         status: "draft",
         amount_value: Decimal.new("1000.00"),
         amount_currency: "USD",
         dashboard_url: "https://dashboard.stripe.com/test/invoices/#{invoice_id}",
         customer_id: "cus_edit_fields"
       }}
    end)

    assert {:ok, result} =
             Accounts.edit_stripe_draft_invoice(account, "in_fields_only", %{
               description: "Annual subscription",
               days_until_due: 45,
               metadata: %{"po_number" => "PO-789"},
               attach_order_form_line_items: false
             })

    assert result.source_document == nil
    assert result.line_items == []
    assert Enum.sort(result.updated_invoice_fields) == [:days_until_due, :description, :metadata]

    assert_received {:update, "in_fields_only", %{description: "Annual subscription", days_until_due: 45}}
    assert_received {:get, "in_fields_only"}
  end

  test "edit_stripe_draft_invoice surfaces the Stripe error when attaching line items fails" do
    account =
      insert_account!(%{
        account_key: "customer:edit-mismatch",
        name: "Edit Mismatch",
        currency: "USD",
        stripe_customer_id: "cus_edit_mismatch"
      })

    insert_order_form!(account, %{
      title: "Mismatch Signed Order Form",
      attributes: %{
        "signed" => true,
        "total" => "1000.00",
        "currency" => "USD"
      }
    })

    StripeClient.put_add_invoice_items(fn {_invoice_id, _line_items, _opts} ->
      {:error, {:invoice_item, "in_currency_mismatch", {:http, 400}}}
    end)

    assert {:error, {:invoice_item, "in_currency_mismatch", {:http, 400}}} =
             Accounts.edit_stripe_draft_invoice(account, "in_currency_mismatch")
  end

  test "returns a clear error when no signed order form exists" do
    account = insert_account!(%{name: "No Forms", stripe_customer_id: "cus_no_forms"})
    insert_document!(account, %{title: "Signed MSA", attributes: %{"signed" => true}})

    assert {:error, :signed_order_form_not_found} =
             Accounts.create_stripe_draft_invoice_from_latest_signed_order_form(account)
  end

  test "returns a clear error when the signed order form has no amount" do
    account = insert_account!(%{name: "Missing Amount", stripe_customer_id: "cus_missing_amount"})

    insert_order_form!(account, %{
      title: "Missing Amount Signed Order Form",
      attributes: %{"signed" => true, "currency" => "USD"}
    })

    assert {:error, :missing_invoice_amount} =
             Accounts.create_stripe_draft_invoice_from_latest_signed_order_form(account)
  end

  test "create uses caller-supplied line items when auto-extraction would miss them" do
    account =
      insert_account!(%{
        account_key: "customer:override",
        name: "Override Customer",
        currency: "USD",
        stripe_customer_id: "cus_override"
      })

    latest =
      insert_order_form!(account, %{
        title: "Multi-page MSA with Order Form",
        document_date: ~D[2026-05-02],
        attributes: %{"signed" => true}
      })

    StripeClient.put_create_draft_invoice(fn {customer_id, attrs, _opts} ->
      assert customer_id == "cus_override"
      assert attrs.currency == "USD"
      assert attrs.metadata["atlas_document_id"] == latest.id

      assert [
               %{
                 amount_cents: 1_620_000,
                 currency: "USD",
                 description: "Tuist SaaS (up to 30 devs)",
                 quantity: 30,
                 period_start: ~D[2026-05-02],
                 period_end: ~D[2027-05-01]
               }
             ] = attrs.line_items

      {:ok,
       %Stripe.Invoice{
         id: "in_override_draft",
         status: "draft",
         amount_value: Decimal.new("16200.00"),
         amount_currency: "USD",
         dashboard_url: "https://dashboard.stripe.com/test/invoices/in_override_draft",
         customer_id: "cus_override"
       }}
    end)

    assert {:ok, result} =
             Accounts.create_stripe_draft_invoice_from_latest_signed_order_form(account,
               line_items: [
                 %{
                   "description" => "Tuist SaaS (up to 30 devs)",
                   "amount" => "16200.00",
                   "currency" => "USD",
                   "quantity" => 30,
                   "period_start" => "2026-05-02",
                   "period_end" => "2027-05-01"
                 }
               ]
             )

    assert result.source_document.id == latest.id
    assert [%{amount_cents: 1_620_000, description: "Tuist SaaS (up to 30 devs)"}] = result.line_items
  end

  test "edit attaches caller-supplied line items without scanning the order form" do
    account =
      insert_account!(%{
        account_key: "customer:edit-override",
        name: "Edit Override Customer",
        currency: "USD",
        stripe_customer_id: "cus_edit_override"
      })

    StripeClient.put_add_invoice_items(fn {invoice_id, line_items, _opts} ->
      assert invoice_id == "in_edit_override"

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
         id: "in_edit_override",
         status: "draft",
         amount_value: Decimal.new("16200.00"),
         amount_currency: "USD",
         dashboard_url: "https://dashboard.stripe.com/test/invoices/in_edit_override",
         customer_id: "cus_edit_override"
       }}
    end)

    assert {:ok, result} =
             Accounts.edit_stripe_draft_invoice(account, "in_edit_override", %{
               line_items: [
                 %{
                   "description" => "Tuist SaaS (up to 30 devs)",
                   "amount" => 16_200,
                   "currency" => "USD",
                   "quantity" => 30
                 }
               ]
             })

    assert result.source_document == nil
    assert [%{amount_cents: 1_620_000}] = result.line_items
  end

  test "create rejects caller-supplied line items missing a description" do
    account =
      insert_account!(%{
        account_key: "customer:bad-items",
        name: "Bad Items Customer",
        currency: "USD",
        stripe_customer_id: "cus_bad_items"
      })

    insert_order_form!(account, %{
      title: "Bad Items Signed Order Form",
      attributes: %{"signed" => true}
    })

    assert {:error, :missing_line_item_description} =
             Accounts.create_stripe_draft_invoice_from_latest_signed_order_form(account,
               line_items: [%{"amount" => "100", "currency" => "USD"}]
             )
  end

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :customer
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_order_form!(%Account{} = account, attrs) do
    document_type = Documents.upsert_document_type("order_form")

    account
    |> insert_document!(Map.put(attrs, :document_type_id, document_type.id))
    |> tap(fn document ->
      insert_page!(
        document,
        "ORDER FORM\n\nThis signed order form sets the annual subscription total for the customer."
      )
    end)
  end

  defp insert_document!(%Account{} = account, attrs) do
    defaults = %{
      title: "Document",
      original_filename: "document.txt",
      content_type: "text/plain",
      byte_size: 10,
      checksum_sha256: "#{System.unique_integer([:positive])}",
      storage_bucket: "test-documents",
      storage_key: "documents/#{System.unique_integer([:positive])}.txt",
      status: "ready",
      source: "upload",
      account_id: account.id
    }

    {foreign_keys, cast_attrs} =
      defaults
      |> Map.merge(attrs)
      |> Map.split([:account_id, :document_type_id, :correspondent_id, :uploaded_by_id])

    %Document{}
    |> Document.changeset(cast_attrs)
    |> Ecto.Changeset.change(foreign_keys)
    |> Repo.insert!()
  end

  defp insert_page!(%Document{} = document, content) do
    %DocumentPage{}
    |> DocumentPage.changeset(%{document_id: document.id, page_number: 1, content: content})
    |> Repo.insert!()
  end
end
