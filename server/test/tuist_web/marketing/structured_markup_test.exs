defmodule TuistWeb.Marketing.StructuredMarkupTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Marketing.StructuredMarkup

  for locale <- ~w(en ja ko es tr zh_Hans) do
    @locale locale
    test "pricing states only the free floor without invented commerce facts (#{locale})" do
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

      # Pro is metered and Enterprise negotiated, so neither gets an `Offer`:
      # search engines reject one without a price, and any price would be made up.
      assert data["offers"] == %{
               "@type" => "AggregateOffer",
               "lowPrice" => "0.00",
               "priceCurrency" => "USD",
               "offerCount" => length(plans),
               "url" => Tuist.Environment.app_url(path: "/pricing"),
               "availability" => "https://schema.org/InStock"
             }
    end
  end

  test "serialized structured data cannot close its script element early" do
    data = %{"@type" => "Article", "articleBody" => ~s[Use </script><script>alert(1)</script> & <b>bold</b>]}

    assert [json] = StructuredMarkup.get_json_serialized_structured_data(%{head_structured_data: [data]})

    refute json =~ "<"
    assert JSON.decode!(json) == data
  end

  test "listing pages link to their entries instead of embedding them" do
    entries = [
      %{id: "2026.11.10-newer", title: "Newer", category: "Product", date: ~D[2026-11-10], body: "<p>Body</p>"},
      %{id: "2026.10.01-older", title: "Older", category: "Product", date: ~D[2026-10-01], body: "<p>Body</p>"}
    ]

    data = StructuredMarkup.get_changelog_structured_data(entries)

    assert data["@type"] == "CollectionPage"

    assert data["mainEntity"] == %{
             "@type" => "ItemList",
             "numberOfItems" => 2,
             "itemListElement" => [
               %{
                 "@type" => "ListItem",
                 "position" => 1,
                 "name" => "Newer",
                 "url" => Tuist.Environment.app_url(path: "/changelog/2026.11.10-newer")
               },
               %{
                 "@type" => "ListItem",
                 "position" => 2,
                 "name" => "Older",
                 "url" => Tuist.Environment.app_url(path: "/changelog/2026.10.01-older")
               }
             ]
           }
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
