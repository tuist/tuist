defmodule Atlas.StripeTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Atlas.Stripe
  alias Atlas.Stripe.Customer
  alias Atlas.Stripe.Invoice

  describe "list_invoices_page/1" do
    test "requests a Stripe invoice page with cursor params" do
      request = fn %Req.Request{} = request ->
        assert URI.to_string(request.url) == "https://api.stripe.com/v1/invoices"
        assert request.options.auth == {:bearer, "sk_test"}
        assert request.options.receive_timeout == 5_000
        assert request.options.params[:limit] == 10
        assert request.options.params[:status] == "open"
        assert request.options.params[:starting_after] == "in_prev"
        refute Keyword.has_key?(request.options.params, :ending_before)

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "data" => [
               %{
                 "id" => "in_next",
                 "number" => "INV-NEXT",
                 "due_date" => 1_779_907_200,
                 "amount_due" => 12_345,
                 "currency" => "eur",
                 "status" => "open",
                 "hosted_invoice_url" => "https://stripe.example/invoices/in_next",
                 "invoice_pdf" => "https://stripe.example/invoices/in_next.pdf",
                 "customer" => "cus_next",
                 "customer_name" => "Next Customer",
                 "customer_email" => "billing@example.com"
               }
             ],
             "has_more" => true
           }
         }}
      end

      assert {:ok, %{invoices: [%Invoice{} = invoice], has_more: true}} =
               Stripe.list_invoices_page(
                 api_key: "sk_test",
                 request: request,
                 limit: 10,
                 status: "open",
                 after: "in_prev"
               )

      assert invoice.id == "in_next"
      assert invoice.number == "INV-NEXT"
      assert invoice.due_date == ~D[2026-05-27]
      assert Decimal.equal?(invoice.amount_value, Decimal.new("123.45"))
      assert invoice.amount_currency == "EUR"
      assert invoice.status == "open"
      assert invoice.hosted_url == "https://stripe.example/invoices/in_next"
      assert invoice.pdf_url == "https://stripe.example/invoices/in_next.pdf"
      assert invoice.customer_id == "cus_next"
      assert invoice.customer_name == "Next Customer"
      assert invoice.customer_email == "billing@example.com"
    end

    test "requests a previous Stripe invoice page" do
      request = fn %Req.Request{} = request ->
        assert request.options.params[:limit] == 25
        assert request.options.params[:ending_before] == "in_first"
        refute Keyword.has_key?(request.options.params, :starting_after)

        {:ok, %Req.Response{status: 200, body: %{"data" => [], "has_more" => false}}}
      end

      assert {:ok, %{invoices: [], has_more: false}} =
               Stripe.list_invoices_page(api_key: "sk_test", request: request, before: "in_first")
    end

    test "returns disabled without an API key" do
      assert :disabled = Stripe.list_invoices_page(api_key: nil)
    end
  end

  describe "create_draft_invoice/3" do
    test "creates a draft invoice, attaches line items, and returns the refreshed invoice" do
      test_pid = self()

      post = fn %Req.Request{} = request ->
        url = URI.to_string(request.url)
        send(test_pid, {:post, url, request.options.form, request.headers})

        case url do
          "https://api.stripe.com/v1/invoices" ->
            {:ok,
             %Req.Response{
               status: 200,
               body: %{
                 "id" => "in_draft",
                 "customer" => "cus_123",
                 "status" => "draft",
                 "currency" => "usd",
                 "amount_due" => 0,
                 "livemode" => false
               }
             }}

          "https://api.stripe.com/v1/invoiceitems" ->
            {:ok, %Req.Response{status: 200, body: %{"id" => "ii_123"}}}
        end
      end

      get = fn %Req.Request{} = request ->
        assert URI.to_string(request.url) == "https://api.stripe.com/v1/invoices/in_draft"

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "id" => "in_draft",
             "customer" => "cus_123",
             "status" => "draft",
             "currency" => "usd",
             "amount_due" => 120_050,
             "due_date" => 1_787_443_200,
             "livemode" => false
           }
         }}
      end

      assert {:ok, %Invoice{} = invoice} =
               Stripe.create_draft_invoice(
                 "cus_123",
                 %{
                   days_until_due: 45,
                   description: "Draft from Atlas",
                   currency: "USD",
                   metadata: %{"atlas_document_id" => "doc_123"},
                   idempotency_key: "atlas-key",
                   line_items: [
                     %{
                       description: "Tuist Enterprise - 25 seats - 2026-06-01 to 2027-05-31",
                       amount_cents: 120_050,
                       currency: "USD",
                       quantity: 25,
                       unit_amount_decimal: "4802",
                       period_start: ~D[2026-06-01],
                       period_end: ~D[2027-05-31],
                       metadata: %{"atlas_document_id" => "doc_123"},
                       idempotency_key: "atlas-key"
                     }
                   ]
                 },
                 api_key: "sk_test",
                 base_url: "https://api.stripe.com/v1/",
                 post: post,
                 get: get
               )

      assert invoice.id == "in_draft"
      assert invoice.status == "draft"
      assert Decimal.equal?(invoice.amount_value, Decimal.new("1200.5"))
      assert invoice.amount_currency == "USD"
      assert invoice.due_date == ~D[2026-08-23]
      assert invoice.dashboard_url == "https://dashboard.stripe.com/test/invoices/in_draft"

      assert_received {:post, "https://api.stripe.com/v1/invoices", invoice_form, invoice_headers}
      assert {"customer", "cus_123"} in invoice_form
      assert {"collection_method", "send_invoice"} in invoice_form
      assert {"auto_advance", "false"} in invoice_form
      assert {"currency", "usd"} in invoice_form
      assert {"days_until_due", 45} in invoice_form
      assert {"metadata[atlas_document_id]", "doc_123"} in invoice_form
      assert invoice_headers["idempotency-key"] == ["atlas-key"]

      assert_received {:post, "https://api.stripe.com/v1/invoiceitems", item_form, item_headers}
      assert {"customer", "cus_123"} in item_form
      assert {"invoice", "in_draft"} in item_form

      refute Enum.any?(item_form, fn {key, _value} ->
               key in ["amount", "price", "pricing[price]", "price_data[product]"]
             end)

      assert {"quantity", 25} in item_form
      assert {"unit_amount_decimal", "4802"} in item_form
      assert {"currency", "usd"} in item_form
      assert {"description", "Tuist Enterprise - 25 seats - 2026-06-01 to 2027-05-31"} in item_form
      assert {"period[start]", 1_780_272_000} in item_form
      assert {"period[end]", 1_811_721_600} in item_form
      assert {"metadata[atlas_document_id]", "doc_123"} in item_form
      assert item_headers["idempotency-key"] == ["atlas-key:line-item:1"]
    end
  end

  describe "get_customer/2" do
    test "fetches a customer" do
      get = fn %Req.Request{} = request ->
        assert URI.to_string(request.url) == "https://api.stripe.com/v1/customers/cus_123"
        assert request.options.auth == {:bearer, "sk_test"}

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "id" => "cus_123",
             "name" => "Acme",
             "email" => "billing@acme.test",
             "address" => %{
               "line1" => "1 Market St",
               "city" => "San Francisco",
               "postal_code" => "94105",
               "country" => "US"
             },
             "livemode" => false
           }
         }}
      end

      assert {:ok, %Customer{} = customer} = Stripe.get_customer("cus_123", api_key: "sk_test", get: get)
      assert customer.id == "cus_123"
      assert customer.email == "billing@acme.test"
      assert customer.address.city == "San Francisco"
      assert customer.dashboard_url == "https://dashboard.stripe.com/test/customers/cus_123"
    end

    test "returns disabled without an API key" do
      assert :disabled = Stripe.get_customer("cus_123", api_key: nil)
    end

    test "returns HTTP errors" do
      get = fn %Req.Request{} = request ->
        assert URI.to_string(request.url) == "https://api.stripe.com/v1/customers/cus_123%2Fneeds%20encoding"

        {:ok,
         %Req.Response{
           status: 404,
           body: %{"error" => %{"message" => "No such customer"}}
         }}
      end

      assert capture_log(fn ->
               assert {:error, {:http, 404}} =
                        Stripe.get_customer("cus_123/needs encoding", api_key: "sk_test", get: get)
             end) =~ "Stripe get_customer failed"
    end

    test "returns transport errors" do
      get = fn %Req.Request{} ->
        {:error, :timeout}
      end

      assert capture_log(fn ->
               assert {:error, :timeout} = Stripe.get_customer("cus_123", api_key: "sk_test", get: get)
             end) =~ "Stripe get_customer transport error"
    end
  end

  describe "update_customer/3" do
    test "updates customer email and address" do
      post = fn %Req.Request{} = request ->
        assert URI.to_string(request.url) == "https://api.stripe.com/v1/customers/cus_123"
        assert {"email", "billing@acme.test"} in request.options.form
        assert {"address[line1]", "1 Market St"} in request.options.form
        assert {"address[postal_code]", "94105"} in request.options.form

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "id" => "cus_123",
             "name" => "Acme",
             "email" => "billing@acme.test",
             "address" => %{
               "line1" => "1 Market St",
               "city" => "San Francisco",
               "postal_code" => "94105",
               "country" => "US"
             },
             "livemode" => false
           }
         }}
      end

      assert {:ok, %Customer{} = customer} =
               Stripe.update_customer(
                 "cus_123",
                 %{
                   email: "billing@acme.test",
                   address: %{line1: "1 Market St", city: "San Francisco", postal_code: "94105"}
                 },
                 api_key: "sk_test",
                 post: post
               )

      assert customer.email == "billing@acme.test"
      assert customer.address.line1 == "1 Market St"
    end

    test "returns disabled without an API key" do
      assert :disabled = Stripe.update_customer("cus_123", %{email: "billing@acme.test"}, api_key: nil)
    end

    test "returns HTTP errors" do
      post = fn %Req.Request{} = request ->
        assert URI.to_string(request.url) == "https://api.stripe.com/v1/customers/cus_123%2Fneeds%20encoding"
        assert {"email", "billing@acme.test"} in request.options.form

        {:ok,
         %Req.Response{
           status: 400,
           body: %{"error" => %{"message" => "Invalid customer"}}
         }}
      end

      assert capture_log(fn ->
               assert {:error, {:http, 400}} =
                        Stripe.update_customer(
                          "cus_123/needs encoding",
                          %{email: "billing@acme.test"},
                          api_key: "sk_test",
                          post: post
                        )
             end) =~ "Stripe update_customer failed"
    end

    test "returns transport errors" do
      post = fn %Req.Request{} ->
        {:error, :timeout}
      end

      assert capture_log(fn ->
               assert {:error, :timeout} =
                        Stripe.update_customer("cus_123", %{email: "billing@acme.test"}, api_key: "sk_test", post: post)
             end) =~ "Stripe update_customer transport error"
    end
  end

  describe "add_invoice_items/3" do
    test "attaches line items to an existing invoice and returns the refreshed invoice" do
      test_pid = self()

      get_call = fn %Req.Request{} = request ->
        url = URI.to_string(request.url)
        send(test_pid, {:get, url})

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "id" => "in_existing",
             "customer" => "cus_existing",
             "status" => "draft",
             "currency" => "usd",
             "amount_due" => 50_000,
             "livemode" => false
           }
         }}
      end

      post = fn %Req.Request{} = request ->
        url = URI.to_string(request.url)
        send(test_pid, {:post, url, request.options.form, request.headers})
        assert url == "https://api.stripe.com/v1/invoiceitems"
        {:ok, %Req.Response{status: 200, body: %{"id" => "ii_new"}}}
      end

      assert {:ok, %Invoice{} = invoice} =
               Stripe.add_invoice_items(
                 "in_existing",
                 [
                   %{
                     description: "Tuist Enterprise - 10 seats",
                     amount_cents: 50_000,
                     currency: "USD",
                     quantity: 10,
                     unit_amount_decimal: "5000",
                     metadata: %{"atlas_document_id" => "doc_existing"},
                     idempotency_key: "atlas-edit"
                   }
                 ],
                 api_key: "sk_test",
                 post: post,
                 get: get_call
               )

      assert invoice.id == "in_existing"
      assert invoice.status == "draft"

      assert_received {:get, "https://api.stripe.com/v1/invoices/in_existing"}
      assert_received {:post, "https://api.stripe.com/v1/invoiceitems", item_form, item_headers}
      assert {"customer", "cus_existing"} in item_form
      assert {"invoice", "in_existing"} in item_form
      assert {"currency", "usd"} in item_form
      assert {"quantity", 10} in item_form
      assert {"unit_amount_decimal", "5000"} in item_form
      assert item_headers["idempotency-key"] == ["atlas-edit:line-item:1"]
      assert_received {:get, "https://api.stripe.com/v1/invoices/in_existing"}
    end

    test "returns disabled without an API key" do
      assert :disabled = Stripe.add_invoice_items("in_existing", [], api_key: nil)
    end
  end

  describe "update_invoice/3" do
    test "posts writable fields to /invoices/:id" do
      test_pid = self()

      post = fn %Req.Request{} = request ->
        send(test_pid, {:post, URI.to_string(request.url), request.options.form})

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "id" => "in_update",
             "customer" => "cus_update",
             "status" => "draft",
             "currency" => "usd",
             "amount_due" => 0,
             "livemode" => false
           }
         }}
      end

      assert {:ok, %Invoice{id: "in_update"}} =
               Stripe.update_invoice(
                 "in_update",
                 %{
                   description: "New description",
                   footer: "Thanks!",
                   days_until_due: 45,
                   metadata: %{"po_number" => "PO-1"}
                 },
                 api_key: "sk_test",
                 post: post
               )

      assert_received {:post, "https://api.stripe.com/v1/invoices/in_update", form}
      assert {"description", "New description"} in form
      assert {"footer", "Thanks!"} in form
      assert {"days_until_due", 45} in form
      assert {"metadata[po_number]", "PO-1"} in form
    end

    test "returns disabled without an API key" do
      assert :disabled = Stripe.update_invoice("in_update", %{description: "x"}, api_key: nil)
    end
  end

  describe "search_customers/2" do
    test "queries /customers/search and decodes the results" do
      test_pid = self()

      request = fn %Req.Request{} = request ->
        send(test_pid, {:search, URI.to_string(request.url), request.options.params})

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "data" => [
               %{
                 "id" => "cus_match",
                 "name" => "Acme Corp, Inc.",
                 "email" => "ap@notion.so",
                 "livemode" => false
               }
             ]
           }
         }}
      end

      assert {:ok, [%Customer{} = customer]} =
               Stripe.search_customers("name:'Acme Corp'", api_key: "sk_test", request: request, limit: 5)

      assert customer.id == "cus_match"
      assert customer.name == "Acme Corp, Inc."
      assert customer.email == "ap@notion.so"
      assert customer.dashboard_url == "https://dashboard.stripe.com/test/customers/cus_match"

      assert_received {:search, "https://api.stripe.com/v1/customers/search", params}
      assert Keyword.get(params, :query) == "name:'Acme Corp'"
      assert Keyword.get(params, :limit) == 5
    end

    test "returns disabled without an API key" do
      assert :disabled = Stripe.search_customers("name:'x'", api_key: nil)
    end
  end

  describe "create_customer/2" do
    test "posts customer fields and address and decodes the response" do
      test_pid = self()

      post = fn %Req.Request{} = request ->
        send(test_pid, {:create, URI.to_string(request.url), request.options.form})

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "id" => "cus_new",
             "name" => "Greenfield Co",
             "email" => "ops@greenfield.dev",
             "address" => %{"line1" => "1 Market St", "city" => "San Francisco"},
             "livemode" => false
           }
         }}
      end

      assert {:ok, %Customer{id: "cus_new"} = customer} =
               Stripe.create_customer(
                 %{
                   name: "Greenfield Co",
                   email: "ops@greenfield.dev",
                   description: "Atlas account",
                   address: %{line1: "1 Market St", city: "San Francisco", postal_code: "94105", country: "US"},
                   metadata: %{"atlas_account_id" => "abc-123"}
                 },
                 api_key: "sk_test",
                 post: post
               )

      assert customer.address.line1 == "1 Market St"

      assert_received {:create, "https://api.stripe.com/v1/customers", form}
      assert {"name", "Greenfield Co"} in form
      assert {"email", "ops@greenfield.dev"} in form
      assert {"description", "Atlas account"} in form
      assert {"address[line1]", "1 Market St"} in form
      assert {"address[city]", "San Francisco"} in form
      assert {"address[postal_code]", "94105"} in form
      assert {"address[country]", "US"} in form
      assert {"metadata[atlas_account_id]", "abc-123"} in form
    end

    test "returns disabled without an API key" do
      assert :disabled = Stripe.create_customer(%{name: "x"}, api_key: nil)
    end
  end

  describe "get_invoice/2" do
    test "retrieves an invoice" do
      get = fn %Req.Request{} = request ->
        assert URI.to_string(request.url) == "https://api.stripe.com/v1/invoices/in_get"

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "id" => "in_get",
             "customer" => "cus_get",
             "status" => "draft",
             "currency" => "usd",
             "amount_due" => 0,
             "livemode" => false
           }
         }}
      end

      assert {:ok, %Invoice{id: "in_get"}} = Stripe.get_invoice("in_get", api_key: "sk_test", get: get)
    end

    test "returns disabled without an API key" do
      assert :disabled = Stripe.get_invoice("in_x", api_key: nil)
    end
  end
end
