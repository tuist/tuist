defmodule Atlas.GTM.Outreach.Apollo do
  @moduledoc false

  alias Atlas.GTM.Outreach.SearchSegments

  @people_search_url "https://api.apollo.io/api/v1/mixed_people/api_search"
  @people_enrichment_url "https://api.apollo.io/api/v1/people/match"
  @organization_search_url "https://api.apollo.io/api/v1/mixed_companies/search"
  @leader_titles [
    "vp engineering",
    "head of platform engineering",
    "director developer productivity",
    "director build infrastructure",
    "head of developer experience",
    "cto"
  ]

  def search_leaders(domain, opts \\ [])

  def search_leaders(domain, opts) when is_binary(domain) and domain != "" do
    search_people(people_search_payload(Keyword.put(opts, :domain, domain)), opts)
  end

  def search_leaders(_domain, _opts), do: {:error, :domain_required}

  def search_leaders_for_company(company, opts \\ [])

  def search_leaders_for_company(%{domain: domain}, opts) when is_binary(domain) and domain != "" do
    search_leaders(domain, opts)
  end

  def search_leaders_for_company(%{company_name: company_name}, opts)
      when is_binary(company_name) and company_name != "" do
    case search_organizations(company_name, opts) do
      {:ok, [organization | _organizations]} ->
        opts =
          opts
          |> Keyword.put(:organization_ids, [organization.id])
          |> Keyword.put_new(:organization_name, organization.name)
          |> Keyword.put_new(:organization_domain, organization.domain)

        search_people(people_search_payload(opts), opts)

      {:ok, []} ->
        {:error, :apollo_organization_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def search_leaders_for_company(_company, _opts), do: {:error, :domain_required}

  def search_organizations(company_name, opts \\ [])

  def search_organizations(company_name, opts) when is_binary(company_name) and company_name != "" do
    payload = %{
      q_organization_name: company_name,
      page: 1,
      per_page: Keyword.get(opts, :organization_per_page, 3)
    }

    with {:ok, result} <- request_organizations(payload, opts) do
      {:ok, result.organizations}
    end
  end

  def search_organizations(_company_name, _opts), do: {:error, :company_name_required}

  def search_outreach_segment(segment_id, opts \\ []) do
    case SearchSegments.get(segment_id) do
      nil ->
        {:error, :unknown_search_segment}

      segment ->
        search_outreach_segment_definition(segment, opts)
    end
  end

  def enrich_person(source_id, opts \\ [])

  def enrich_person(source_id, opts) when is_binary(source_id) and source_id != "" do
    request = request(opts)

    with {:ok, api_key} <- api_key(opts),
         {:ok, %{status: 200, body: %{"person" => person}}} when is_map(person) <-
           request.(
             url: @people_enrichment_url,
             headers: headers(api_key),
             params: [id: source_id, reveal_personal_emails: false, reveal_phone_number: false]
           ),
         contact when not is_nil(contact) <- contact_attrs(person, opts) do
      {:ok, contact}
    else
      {:ok, %{status: 200}} ->
        {:error, :apollo_person_not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, "Apollo person enrichment returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}

      nil ->
        {:error, :apollo_person_not_found}
    end
  end

  def enrich_person(_source_id, _opts), do: {:error, :apollo_person_id_required}

  defp search_outreach_segment_definition(segment, opts) do
    with {:ok, organization_result} <-
           request_organizations(segment_organization_payload(segment), opts) do
      {organizations, excluded_organizations} =
        Enum.split_with(organization_result.organizations, fn organization ->
          is_nil(SearchSegments.organization_exclusion(segment, organization))
        end)

      organizations_by_id = Map.new(organizations, &{&1.id, &1})

      search_people_for_segment(segment, organizations_by_id, excluded_organizations, opts)
    end
  end

  defp search_people_for_segment(segment, organizations_by_id, excluded_organizations, _opts)
       when map_size(organizations_by_id) == 0 do
    {:ok,
     %{
       segment: segment,
       definition: SearchSegments.snapshot(segment),
       total: 0,
       people: [],
       excluded: length(excluded_organizations)
     }}
  end

  defp search_people_for_segment(segment, organizations_by_id, excluded_organizations, opts) do
    with {:ok, people_result} <-
           request_people(
             segment_people_payload(segment, Map.keys(organizations_by_id)),
             Keyword.put(opts, :organizations_by_id, organizations_by_id)
           ) do
      {people, excluded_people} =
        Enum.split_with(people_result.people, fn person ->
          is_nil(SearchSegments.person_exclusion(segment, person))
        end)

      {:ok,
       %{
         segment: segment,
         definition: SearchSegments.snapshot(segment),
         total: people_result.total,
         people: people,
         excluded: length(excluded_organizations) + length(excluded_people)
       }}
    end
  end

  defp segment_organization_payload(segment) do
    %{
      organization_num_employees_ranges: segment.organization_num_employees_ranges,
      q_organization_keyword_tags: segment.organization_keyword_tags,
      page: 1,
      per_page: segment.organization_limit
    }
  end

  defp segment_people_payload(segment, organization_ids) do
    %{
      person_titles: segment.titles,
      person_seniorities: segment.seniorities,
      include_similar_titles: false,
      organization_ids: organization_ids,
      page: 1,
      per_page: segment.people_limit
    }
  end

  defp search_people(payload, opts) do
    with {:ok, result} <- request_people(payload, opts) do
      {:ok, result.people}
    end
  end

  defp request_people(payload, opts) do
    request = request(opts)

    with {:ok, api_key} <- api_key(opts),
         {:ok, %{status: 200, body: body}} <-
           request.(url: @people_search_url, headers: headers(api_key), json: payload) do
      {:ok, %{people: contacts(body, opts), total: result_total(body)}}
    else
      {:ok, %{status: status, body: body}} ->
        {:error, "Apollo people search returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request_organizations(payload, opts) do
    request = request(opts)

    with {:ok, api_key} <- api_key(opts),
         {:ok, %{status: 200, body: body}} <-
           request.(url: @organization_search_url, headers: headers(api_key), json: payload) do
      {:ok, %{organizations: organizations(body), total: result_total(body)}}
    else
      {:ok, %{status: status, body: body}} ->
        {:error, "Apollo organization search returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp people_search_payload(opts) do
    %{
      person_titles: Keyword.get(opts, :titles, @leader_titles),
      page: 1,
      per_page: Keyword.get(opts, :per_page, 5)
    }
    |> maybe_put(:q_organization_domains_list, domain_list(opts))
    |> maybe_put(:organization_ids, Keyword.get(opts, :organization_ids))
  end

  defp contacts(body, opts) do
    body
    |> Map.get("people", [])
    |> Enum.map(&contact_attrs(&1, opts))
    |> Enum.reject(&is_nil/1)
  end

  defp contact_attrs(person, opts) when is_map(person) do
    title = person["title"]
    organization_id = person["organization_id"] || get_in(person, ["organization", "id"])
    organization = organization_for(person, organization_id, opts)

    # A non-empty id is required: it becomes source_id, the key used to
    # deduplicate and enroll candidates. People without one cannot be persisted.
    if is_binary(person["id"]) and person["id"] != "" and is_binary(title) and title != "" do
      %{
        source: "apollo",
        source_id: person["id"],
        full_name: person_name(person),
        title: title,
        organization_name: organization.name || person["organization_name"] || Keyword.get(opts, :organization_name),
        linkedin_url: person["linkedin_url"],
        email: visible_email(person["email"]),
        confidence: title_confidence(title),
        metadata:
          %{
            "apollo_id" => person["id"],
            "city" => person["city"],
            "state" => person["state"],
            "country" => person["country"],
            "seniority" => person["seniority"],
            "organization_id" => organization_id,
            "organization_domain" => organization.domain,
            "organization_metadata" => non_empty_map(organization.metadata)
          }
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()
      }
    end
  end

  defp contact_attrs(_person, _opts), do: nil

  defp organization_for(person, organization_id, opts) do
    organization = get_in(person, ["organization"]) || %{}
    organizations_by_id = Keyword.get(opts, :organizations_by_id, %{})

    case Map.get(organizations_by_id, organization_id) do
      nil ->
        %{
          name: organization["name"],
          domain: organization_domain(organization) || Keyword.get(opts, :organization_domain),
          metadata: organization_metadata(organization)
        }

      matched ->
        matched
    end
  end

  defp organizations(body) do
    body
    |> Map.get("organizations", [])
    |> Enum.map(&organization_attrs/1)
    |> Enum.reject(&is_nil/1)
  end

  defp organization_attrs(organization) when is_map(organization) do
    id = organization["id"] || organization["organization_id"]

    if is_binary(id) and id != "" do
      %{
        id: id,
        name: organization["name"],
        domain: organization_domain(organization),
        metadata: organization_metadata(organization)
      }
    end
  end

  defp organization_attrs(_organization), do: nil

  defp organization_metadata(organization) do
    %{
      "naics_codes" => organization["naics_codes"],
      "keywords" => organization["keywords"],
      "industry" => organization["industry"],
      "estimated_num_employees" => organization["estimated_num_employees"],
      "country" => organization["country"]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp organization_domain(organization) do
    [
      organization["primary_domain"],
      organization["website_url"],
      organization["domain"]
    ]
    |> Enum.find(&is_binary/1)
    |> normalize_domain()
  end

  defp result_total(body) do
    body["total_entries"] || get_in(body, ["pagination", "total_entries"]) ||
      get_in(body, ["pagination", "total"]) || 0
  end

  defp person_name(person) do
    [
      person["name"],
      [person["first_name"], person["last_name"] || person["last_name_obfuscated"]]
      |> Enum.filter(&is_binary/1)
      |> Enum.join(" ")
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.find(&(&1 != ""))
  end

  defp visible_email(email) when is_binary(email) and email not in ["email_not_unlocked", ""], do: email
  defp visible_email(_email), do: nil

  defp non_empty_map(value) when is_map(value) and map_size(value) > 0, do: value
  defp non_empty_map(_value), do: nil

  defp title_confidence(title) do
    normalized = String.downcase(title)

    cond do
      String.contains?(normalized, "developer productivity") -> 95
      String.contains?(normalized, "build") -> 92
      String.contains?(normalized, "platform") -> 88
      String.contains?(normalized, "mobile") -> 86
      String.contains?(normalized, "vp") -> 82
      String.contains?(normalized, "cto") -> 80
      true -> 65
    end
  end

  defp api_key(opts) do
    case Keyword.get(opts, :api_key) || Application.get_env(:atlas, :gtm_outreach, [])[:apollo_api_key] do
      key when is_binary(key) and key != "" -> {:ok, key}
      _missing -> {:error, :apollo_api_key_not_configured}
    end
  end

  defp headers(api_key), do: [{"X-Api-Key", api_key}, {"Content-Type", "application/json"}]

  defp request(opts), do: Keyword.get(opts, :request, &Req.post/1)

  defp domain_list(opts) do
    case Keyword.get(opts, :domain) do
      domain when is_binary(domain) and domain != "" -> [normalize_domain(domain)]
      _domain -> []
    end
  end

  defp normalize_domain(nil), do: nil

  defp normalize_domain(domain) when is_binary(domain) do
    domain
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/^https?:\/\//, "")
    |> String.replace(~r/^www\./, "")
    |> String.split("/", parts: 2)
    |> List.first()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
