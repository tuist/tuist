defmodule Atlas.Accounts.OrderFormsTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.OrderForms
  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage

  describe "signed?/2" do
    test "detects signed via attributes flag" do
      doc = build_order_form_document(attributes: %{"signed" => true}, title: "Notion Order Form")
      assert OrderForms.signed?(doc)
    end

    test "detects signed via signed_at attribute" do
      doc = build_order_form_document(attributes: %{"signed_at" => "2026-06-10"}, title: "Notion Order Form")
      assert OrderForms.signed?(doc)
    end

    test "detects signed via 'signed order form' in context" do
      doc =
        build_order_form_document(
          attributes: %{"total" => "1000.00"},
          title: "Signed Order Form 2026"
        )

      assert OrderForms.signed?(doc)
    end

    test "detects signed via 'fully executed' in page body" do
      doc =
        build_order_form_document(
          attributes: %{"total" => "1000.00"},
          title: "Order Form 2026",
          pages: [%DocumentPage{page_number: 1, content: "This Order Form is fully executed by both parties."}]
        )

      assert OrderForms.signed?(doc)
    end

    test "does not falsely match a draft order form whose page body mentions 'signed order form'" do
      doc =
        build_order_form_document(
          attributes: %{"total" => "1000.00"},
          title: "Draft Order Form 2027",
          pages: [
            %DocumentPage{
              page_number: 1,
              content: "ORDER FORM\n\nThis signed order form template defines the annual subscription."
            }
          ]
        )

      refute OrderForms.signed?(doc)
    end

    test "skips documents that are not order forms at all" do
      doc =
        build_order_form_document(
          attributes: %{"signed" => true},
          title: "Master Services Agreement",
          document_type_name: "contract",
          original_filename: "msa.pdf",
          pages: [%DocumentPage{page_number: 1, content: "This is a master services agreement, fully executed."}]
        )

      refute OrderForms.signed?(doc)
    end

    test "accepts pages passed explicitly when not preloaded" do
      doc = build_order_form_document(attributes: %{}, title: "Order Form", pages: :not_loaded)
      pages = [%DocumentPage{page_number: 1, content: "Signed by Alice on 2026-06-10."}]

      assert OrderForms.signed?(doc, pages)
    end
  end

  describe "commercial_attrs/2" do
    test "extracts currency, contract value, and renewal date from extracted attributes" do
      doc =
        build_order_form_document(
          attributes: %{
            "signed" => true,
            "currency" => "USD",
            "total_amount" => "16200.00",
            "start_date" => "2026-05-02",
            "end_date" => "2027-05-01"
          }
        )

      account = %Account{deal_stage: nil, poc_end_date: nil}

      attrs = OrderForms.commercial_attrs(doc, account)

      assert attrs.currency == "USD"
      assert Decimal.equal?(attrs.current_value, Decimal.new("16200"))
      assert attrs.next_renewal_date == ~D[2027-05-01]
      assert attrs.segment == :customer
      assert attrs.deal_stage == "closed_won"
      assert attrs.poc_end_date == ~D[2027-05-01]
    end

    test "fills blank deal_stage and poc_end_date but never overwrites curated values" do
      doc =
        build_order_form_document(
          attributes: %{
            "signed" => true,
            "currency" => "EUR",
            "total" => "1000",
            "end_date" => "2027-05-01"
          }
        )

      account = %Account{deal_stage: "negotiation", poc_end_date: ~D[2026-08-15]}

      attrs = OrderForms.commercial_attrs(doc, account)

      assert attrs.segment == :customer
      assert attrs.currency == "EUR"
      refute Map.has_key?(attrs, :deal_stage)
      refute Map.has_key?(attrs, :poc_end_date)
    end

    test "omits fields the order form does not carry" do
      doc = build_order_form_document(attributes: %{"signed" => true})
      account = %Account{deal_stage: nil, poc_end_date: nil}

      attrs = OrderForms.commercial_attrs(doc, account)

      assert attrs == %{segment: :customer, deal_stage: "closed_won"}
    end
  end

  describe "billing_email/2" do
    test "extracts billing email from structured attributes" do
      doc =
        build_order_form_document(
          attributes: %{
            "billing_details" => %{
              "email" => "Accounts@SafetyCulture.IO"
            }
          }
        )

      assert OrderForms.billing_email(doc) == "accounts@safetyculture.io"
    end

    test "extracts billing email from the billing section instead of the sales contact" do
      doc =
        build_order_form_document(
          attributes: %{},
          pages: [
            %DocumentPage{
              page_number: 1,
              content: """
              Order Details
              Sales Contact               Pedro Pinera
              Email                       pedro@tuist.dev

              Customer Details
              Bill Details
              Company                     SafetyCulture Pty Ltd
              Sold to Name                SafetyCulture Pty Ltd
              Bill to Name                SafetyCulture
              Email                       accounts@safetyculture.io
              Phone                       NA
              """
            }
          ]
        )

      assert OrderForms.billing_email(doc) == "accounts@safetyculture.io"
    end
  end

  describe "billing_address/2" do
    test "extracts billing address from structured attributes" do
      doc =
        build_order_form_document(
          attributes: %{
            "billing_details" => %{
              "address" => %{
                "street" => "72 Foveaux Street",
                "city" => "Surry Hills",
                "zip" => "2010",
                "country" => "Australia"
              }
            }
          }
        )

      assert OrderForms.billing_address(doc) == %{
               line1: "72 Foveaux Street",
               city: "Surry Hills",
               postal_code: "2010",
               country: "AU"
             }
    end

    test "extracts billing address from the billing section" do
      doc =
        build_order_form_document(
          attributes: %{},
          pages: [
            %DocumentPage{
              page_number: 1,
              content: """
              Order Details
              Sales Contact               Pedro Pinera
              Email                       pedro@tuist.dev

              Customer Details
              Bill Details
              Company                     SafetyCulture Pty Ltd
              Email                       accounts@safetyculture.io
              Address                     72 Foveaux Street
              City                        Surry Hills
              ZIP/Postal Code             2010
              Country                     Australia
              """
            }
          ]
        )

      assert OrderForms.billing_address(doc) == %{
               line1: "72 Foveaux Street",
               city: "Surry Hills",
               postal_code: "2010",
               country: "AU"
             }
    end
  end

  defp build_order_form_document(opts) do
    document_type = %Documents.DocumentType{
      id: Ecto.UUID.generate(),
      name: Keyword.get(opts, :document_type_name, "order_form")
    }

    %Document{
      id: Ecto.UUID.generate(),
      title: Keyword.get(opts, :title, "Order Form"),
      original_filename: Keyword.get(opts, :original_filename, "order-form.pdf"),
      attributes: Keyword.fetch!(opts, :attributes),
      document_type: document_type,
      tags: [],
      pages: Keyword.get(opts, :pages, [])
    }
  end
end
