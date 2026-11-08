defmodule TuistWeb.Marketing.StructuredMarkupTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Marketing.StructuredMarkup

  for locale <- ~w(en ja ko es tr zh_Hans) do
    @locale locale
    test "pricing offers reflect the pricing contract without invented commerce facts (#{locale})" do
      Gettext.put_locale(TuistWeb.Gettext, @locale)
      plans = Tuist.Billing.get_plans()

      data =
        plans
        |> StructuredMarkup.get_pricing_plans_structured_data()
        |> JSON.encode!()
        |> JSON.decode!()

      assert data["@type"] == "Product"
      assert data["brand"]["@type"] in ["Brand", "Organization"]
      assert data["brand"]["name"] == "Tuist"
      refute Map.has_key?(data, "aggregateRating")
      refute Map.has_key?(data, "review")
      assert length(data["offers"]) == length(plans)

      for {plan, offer} <- Enum.zip(plans, data["offers"]) do
        assert offer["@type"] == "Offer"
        assert offer["name"] == "Tuist #{plan.name}"
        assert offer["description"] == plan.description
        assert offer["url"] == Tuist.Environment.app_url(path: "/pricing")

        for key <-
              ~w(priceValidUntil validFrom validThrough hasMerchantReturnPolicy shippingDetails) do
          refute Map.has_key?(offer, key)
        end

        case plan.id do
          :air ->
            assert offer["price"] == "0.00"
            assert offer["priceCurrency"] == "USD"

          id when id in [:pro, :enterprise] ->
            refute Map.has_key?(offer, "price")
            refute Map.has_key?(offer, "priceCurrency")
            refute Map.has_key?(offer, "priceSpecification")
        end
      end
    end
  end

  test "pricing uses plan identity rather than localized display prices" do
    plans = [
      %{id: :air, name: "Air", price: "Kostenlos", description: "Gratis innerhalb der Limits"},
      %{id: :pro, name: "Pro", price: "$0", description: "Nutzungsabhängig"},
      %{
        id: :enterprise,
        name: "Enterprise",
        price: "Individuell",
        description: "Nach Vereinbarung"
      }
    ]

    assert %{"offers" => [air, pro, enterprise]} =
             StructuredMarkup.get_pricing_plans_structured_data(plans)

    assert air["price"] == "0.00"
    refute Map.has_key?(pro, "price")
    refute Map.has_key?(enterprise, "price")
  end

  test "FAQ structured data preserves plain answers and extracts text from HTML" do
    data =
      StructuredMarkup.get_faq_structured_data([
        {"Can I cancel?", "Yes, at any time."},
        {"Where can I learn more?", ~s(Read <a href="/compare">comparison guides</a> &amp; <strong>pricing</strong>.)}
      ])

    assert data == %{
             "@context" => "https://schema.org",
             "@type" => "FAQPage",
             "mainEntity" => [
               %{
                 "@type" => "Question",
                 "name" => "Can I cancel?",
                 "acceptedAnswer" => %{"@type" => "Answer", "text" => "Yes, at any time."}
               },
               %{
                 "@type" => "Question",
                 "name" => "Where can I learn more?",
                 "acceptedAnswer" => %{
                   "@type" => "Answer",
                   "text" => "Read comparison guides & pricing."
                 }
               }
             ]
           }
  end
end
