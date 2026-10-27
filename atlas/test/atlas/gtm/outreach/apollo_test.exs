defmodule Atlas.GTM.Outreach.ApolloTest do
  use ExUnit.Case, async: true

  alias Atlas.GTM.Outreach.Apollo

  test "searches the global mobile-leader segment and excludes consultancies and irrelevant roles" do
    parent = self()

    request = fn opts ->
      send(parent, {:apollo_segment_request, opts})
      assert {"X-Api-Key", "apollo-key"} in opts[:headers]

      case opts[:url] do
        "https://api.apollo.io/api/v1/mixed_companies/search" ->
          assert opts[:json].organization_num_employees_ranges == ["200,5000"]

          assert opts[:json].q_organization_keyword_tags == [
                   "fintech",
                   "banking",
                   "payments",
                   "e-commerce",
                   "retail",
                   "travel",
                   "mobility",
                   "gaming",
                   "food delivery",
                   "transportation"
                 ]

          refute Map.has_key?(opts[:json], :organization_locations)
          assert opts[:json].per_page == 100

          {:ok,
           %{
             status: 200,
             body: %{
               "organizations" => [
                 %{
                   "id" => "product-org",
                   "name" => "Acme Platforms",
                   "primary_domain" => "acme.example",
                   "naics_codes" => ["522320"],
                   "estimated_num_employees" => 800
                 },
                 %{
                   "id" => "agency-org",
                   "name" => "Agency Labs",
                   "primary_domain" => "agency.example",
                   "naics_codes" => ["541511"]
                 }
               ],
               "pagination" => %{"total_entries" => 300}
             }
           }}

        "https://api.apollo.io/api/v1/mixed_people/api_search" ->
          assert opts[:json].organization_ids == ["product-org"]

          assert opts[:json].person_titles == [
                   "head of mobile",
                   "director of mobile engineering",
                   "mobile engineering manager",
                   "head of ios"
                 ]

          assert opts[:json].person_seniorities == ["manager", "director", "head", "vp"]
          assert opts[:json].include_similar_titles == false
          assert opts[:json].per_page == 50

          {:ok,
           %{
             status: 200,
             body: %{
               "people" => [
                 %{
                   "id" => "person-1",
                   "name" => "Jordan Lee",
                   "title" => "Director of Mobile Engineering",
                   "organization_id" => "product-org",
                   "linkedin_url" => "https://linkedin.com/in/jordan-lee",
                   "country" => "United States"
                 },
                 %{
                   "id" => "person-2",
                   "name" => "Taylor Smith",
                   "title" => "Head of Mobile Networks",
                   "organization_id" => "product-org"
                 }
               ],
               "pagination" => %{"total_entries" => 1461}
             }
           }}
      end
    end

    assert {:ok, result} =
             Apollo.search_outreach_segment("mobile_mid_large", api_key: "apollo-key", request: request)

    assert_receive {:apollo_segment_request, _organization_request}
    assert_receive {:apollo_segment_request, _people_request}

    assert result.total == 1461
    assert result.excluded == 2
    assert [jordan] = result.people
    assert jordan.source_id == "person-1"
    assert jordan.organization_name == "Acme Platforms"
    assert jordan.metadata["organization_domain"] == "acme.example"
    assert jordan.metadata["country"] == "United States"
  end

  test "searches leaders by normalized company domain and maps visible Apollo people" do
    parent = self()

    request = fn opts ->
      send(parent, {:apollo_request, opts})

      assert opts[:url] == "https://api.apollo.io/api/v1/mixed_people/api_search"
      assert {"X-Api-Key", "apollo-key"} in opts[:headers]
      assert opts[:json].q_organization_domains_list == ["acme.example"]
      assert opts[:json].person_titles == ["head of developer experience"]
      assert opts[:json].per_page == 2

      {:ok,
       %{
         status: 200,
         body: %{
           "people" => [
             %{
               "id" => "person-1",
               "name" => "Riley Stone",
               "title" => "Head of Developer Experience",
               "organization" => %{"id" => "org-1", "name" => "Acme Platforms"},
               "linkedin_url" => "https://linkedin.com/in/riley-stone",
               "email" => "email_not_unlocked",
               "city" => "Berlin",
               "country" => "Germany",
               "seniority" => "head"
             },
             %{
               "id" => "person-2",
               "name" => "No Title"
             }
           ]
         }
       }}
    end

    assert {:ok, [contact]} =
             Apollo.search_leaders("https://www.Acme.example/mobile",
               api_key: "apollo-key",
               request: request,
               titles: ["head of developer experience"],
               per_page: 2
             )

    assert_receive {:apollo_request, _opts}

    assert contact == %{
             source: "apollo",
             source_id: "person-1",
             full_name: "Riley Stone",
             title: "Head of Developer Experience",
             organization_name: "Acme Platforms",
             linkedin_url: "https://linkedin.com/in/riley-stone",
             email: nil,
             confidence: 65,
             metadata: %{
               "apollo_id" => "person-1",
               "city" => "Berlin",
               "country" => "Germany",
               "seniority" => "head",
               "organization_id" => "org-1"
             }
           }
  end

  test "resolves a domainless opportunity company before searching people" do
    parent = self()

    request = fn opts ->
      send(parent, {:apollo_request, opts})

      case opts[:url] do
        "https://api.apollo.io/api/v1/mixed_companies/search" ->
          assert opts[:json].q_organization_name == "Acme Platforms"
          assert opts[:json].per_page == 1

          {:ok,
           %{
             status: 200,
             body: %{
               "organizations" => [
                 %{
                   "id" => "org-1",
                   "name" => "Acme Platforms",
                   "website_url" => "https://www.acme.example/careers"
                 }
               ]
             }
           }}

        "https://api.apollo.io/api/v1/mixed_people/api_search" ->
          assert opts[:json].organization_ids == ["org-1"]
          refute Map.has_key?(opts[:json], :q_organization_domains_list)

          {:ok,
           %{
             status: 200,
             body: %{
               "people" => [
                 %{
                   "id" => "person-1",
                   "first_name" => "Sam",
                   "last_name_obfuscated" => "Rivera",
                   "title" => "Head of Platform Engineering",
                   "organization_id" => "org-1",
                   "linkedin_url" => "https://linkedin.com/in/sam-rivera",
                   "email" => "sam@example.com"
                 }
               ]
             }
           }}
      end
    end

    assert {:ok, [contact]} =
             Apollo.search_leaders_for_company(%{company_name: "Acme Platforms", domain: nil},
               api_key: "apollo-key",
               request: request,
               organization_per_page: 1
             )

    assert_receive {:apollo_request, [url: "https://api.apollo.io/api/v1/mixed_companies/search", headers: _, json: _]}
    assert_receive {:apollo_request, [url: "https://api.apollo.io/api/v1/mixed_people/api_search", headers: _, json: _]}

    assert contact.full_name == "Sam Rivera"
    assert contact.organization_name == "Acme Platforms"
    assert contact.email == "sam@example.com"
    assert contact.confidence == 88
    assert contact.metadata["organization_id"] == "org-1"
    assert contact.metadata["organization_domain"] == "acme.example"
  end

  test "returns useful errors for missing Apollo configuration and unresolved companies" do
    assert {:error, :apollo_api_key_not_configured} = Apollo.search_leaders("acme.example")

    request = fn _opts ->
      {:ok, %{status: 200, body: %{"organizations" => []}}}
    end

    assert {:error, :apollo_organization_not_found} =
             Apollo.search_leaders_for_company(%{company_name: "Unknown"}, api_key: "apollo-key", request: request)
  end
end
