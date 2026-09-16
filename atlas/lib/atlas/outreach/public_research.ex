defmodule Atlas.Outreach.PublicResearch do
  @moduledoc """
  Searches public sources for outreach context and records what the agent used.
  """

  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Audit
  alias Atlas.MCP.Tools.SearchWeb
  alias Atlas.Repo
  alias Atlas.Search
  alias Atlas.Slack.URLContent

  @default_count 5
  @maximum_count 5

  @doc """
  Searches several public-source categories that are useful for confirming a
  person's identity and finding authored work.

  The searches deliberately keep the contact's employer in every query. A
  matching name alone is not enough evidence that a profile belongs to the
  contact.
  """
  def research_person(%Contact{} = contact) do
    contact = Repo.preload(contact, :account)
    searches = person_searches(contact)

    with {:ok, completed_searches} <- run_searches(searches),
         {:ok, event} <- record_person_research(contact, completed_searches) do
      {:ok,
       %{
         event_id: event.id,
         searches: Enum.map(completed_searches, &search_payload/1)
       }}
    end
  end

  def search(%Contact{} = contact, params) when is_map(params) do
    params = Map.put(params, "count", normalize_count(Map.get(params, "count")))

    with {:ok, payload} <- SearchWeb.execute(nil, params),
         {:ok, event} <- record_search(contact, payload) do
      {:ok,
       %{
         event_id: event.id,
         query: payload.query,
         results: payload.results
       }}
    end
  end

  @doc """
  Reads a public page discovered during contact research and records its text as
  timeline evidence.
  """
  def read_page(%Contact{} = contact, %{"url" => url}) when is_binary(url) do
    with {:ok, page} <- URLContent.fetch(url),
         {:ok, event} <- record_page_research(contact, page) do
      {:ok,
       %{
         event_id: event.id,
         url: page.final_url,
         title: page.title,
         content: page.content,
         truncated: page.truncated
       }}
    end
  end

  def read_page(%Contact{}, _params), do: {:error, "A web address is required."}

  defp run_searches(searches) do
    Enum.reduce_while(searches, {:ok, []}, fn search, {:ok, completed} ->
      params = %{"query" => search.query, "count" => @default_count}

      case SearchWeb.execute(nil, params) do
        {:ok, payload} ->
          completed_search = Map.put(search, :results, payload.results)
          {:cont, {:ok, [completed_search | completed]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, completed} -> {:ok, completed |> Enum.reverse() |> deduplicate_results()}
      error -> error
    end
  end

  defp record_person_research(contact, searches) do
    results = Enum.flat_map(searches, & &1.results)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    first_result = List.first(results)

    result =
      %Event{account_id: contact.account_id, contact_id: contact.id}
      |> Event.changeset(%{
        external_id: "outreach-person-research:#{Ecto.UUID.generate()}",
        source: "web",
        kind: "research",
        title: "Public profile research for #{contact.full_name}",
        body: person_research_body(searches),
        occurred_at: now,
        url: first_result && first_result.url,
        metadata: %{
          "research_type" => "person",
          "queries" => Enum.map(searches, & &1.query),
          "result_count" => length(results),
          "results" => Enum.flat_map(searches, &person_result_metadata/1)
        }
      })
      |> Repo.insert()

    case result do
      {:ok, event} ->
        Search.index_account_event(event)
        audit_person_research(contact, event, searches)
        {:ok, event}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp record_search(contact, payload) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    first_result = List.first(payload.results)

    result =
      %Event{account_id: contact.account_id, contact_id: contact.id}
      |> Event.changeset(%{
        external_id: "outreach-public-research:#{Ecto.UUID.generate()}",
        source: "web",
        kind: "research",
        title: "Public research for #{contact.full_name}",
        body: research_body(payload.query, payload.results),
        occurred_at: now,
        url: first_result && first_result.url,
        metadata: %{
          "query" => payload.query,
          "result_count" => length(payload.results),
          "results" => Enum.map(payload.results, &result_metadata/1)
        }
      })
      |> Repo.insert()

    case result do
      {:ok, event} ->
        Search.index_account_event(event)
        audit_search(contact, event, payload)
        {:ok, event}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp record_page_research(contact, page) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    result =
      %Event{account_id: contact.account_id, contact_id: contact.id}
      |> Event.changeset(%{
        external_id: "outreach-page-research:#{Ecto.UUID.generate()}",
        source: "web",
        kind: "research",
        title: page.title || "Public page research for #{contact.full_name}",
        body: page_research_body(page),
        occurred_at: now,
        url: page.final_url,
        metadata: %{
          "research_type" => "public_page",
          "content_type" => page.content_type,
          "redirects_followed" => page.redirects_followed,
          "truncated" => page.truncated,
          "url" => page.final_url
        }
      })
      |> Repo.insert()

    case result do
      {:ok, event} ->
        Search.index_account_event(event)
        audit_page_research(contact, event, page)
        {:ok, event}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp research_body(query, []) do
    "Search: #{query}\n\nNo relevant public results were found."
  end

  defp research_body(query, results) do
    entries =
      Enum.map_join(results, "\n\n", fn result ->
        title = truncate(result.title, 240)
        snippet = truncate(result.snippet, 600)

        ["- #{title}", snippet, result.url]
        |> Enum.reject(&blank?/1)
        |> Enum.join("\n")
      end)

    "Search: #{query}\n\n#{entries}"
  end

  defp person_research_body(searches) do
    coverage =
      Enum.map_join(searches, "\n", fn search ->
        "- **#{search.label}:** `#{search.query}`"
      end)

    results =
      Enum.map_join(searches, "\n\n", fn search ->
        "### #{search.label}\n\n#{person_search_results(search.results)}"
      end)

    "## Sources searched\n\n#{coverage}\n\n## Results\n\n#{results}"
  end

  defp person_search_results([]), do: "No relevant public results were found."

  defp person_search_results(results) do
    Enum.map_join(results, "\n\n", fn result ->
      title = truncate(result.title, 240)
      snippet = truncate(result.snippet, 600)

      ["- **#{title}**", snippet && "  #{snippet}", result.url && "  <#{result.url}>"]
      |> Enum.reject(&blank?/1)
      |> Enum.join("\n")
    end)
  end

  defp page_research_body(page) do
    heading = page.title && "## #{page.title}\n\n"
    truncation_note = if page.truncated, do: "\n\n_Content was truncated._", else: ""

    "Source: <#{page.final_url}>\n\n#{heading}#{page.content}#{truncation_note}"
  end

  defp person_searches(contact) do
    name = quoted(contact.full_name)
    company = quoted(contact.account.name)
    title = quoted(contact.title)
    identity = Enum.reject([name, company, title], &blank?/1) |> Enum.join(" ")

    [
      %{
        key: "identity",
        label: "Identity and role",
        query: identity
      },
      %{
        key: "company",
        label: "Company sources",
        query: company_query(contact.account.primary_domain, name, company)
      },
      %{
        key: "github",
        label: "GitHub profiles and public work",
        query: Enum.reject(["site:github.com", name, company], &blank?/1) |> Enum.join(" ")
      },
      %{
        key: "authored",
        label: "Personal sites and authored work",
        query:
          Enum.reject(
            [name, company, "(blog OR podcast OR speaker OR conference OR portfolio)", "-site:linkedin.com"],
            &blank?/1
          )
          |> Enum.join(" ")
      }
    ]
  end

  defp company_query(domain, name, _company) when is_binary(domain) and domain != "" do
    Enum.reject(["site:#{domain}", name], &blank?/1) |> Enum.join(" ")
  end

  defp company_query(_domain, name, company) do
    Enum.reject([name, company, "official"], &blank?/1) |> Enum.join(" ")
  end

  defp deduplicate_results(searches) do
    {searches, _seen} =
      Enum.map_reduce(searches, MapSet.new(), fn search, seen ->
        {results, seen} =
          Enum.reduce(search.results, {[], seen}, fn result, {results, seen} ->
            if MapSet.member?(seen, result.url) do
              {results, seen}
            else
              {[result | results], MapSet.put(seen, result.url)}
            end
          end)

        {%{search | results: Enum.reverse(results)}, seen}
      end)

    searches
  end

  defp search_payload(search) do
    %{source: search.key, label: search.label, query: search.query, results: search.results}
  end

  defp person_result_metadata(search) do
    Enum.map(search.results, fn result ->
      result_metadata(result)
      |> Map.put("source", search.key)
    end)
  end

  defp result_metadata(result) do
    %{
      "title" => result.title,
      "url" => result.url,
      "snippet" => result.snippet,
      "age" => result.age
    }
  end

  defp audit_search(contact, event, payload) do
    Audit.record(
      "outreach.public_research_completed",
      %{
        target_type: "contact",
        target_id: contact.id,
        target_label: contact.full_name,
        metadata: %{
          "account_id" => contact.account_id,
          "event_id" => event.id,
          "path" => "/gtm/outreach/#{contact.id}",
          "query" => payload.query,
          "result_count" => length(payload.results)
        }
      }
    )
  end

  defp audit_person_research(contact, event, searches) do
    Audit.record(
      "outreach.public_research_completed",
      %{
        target_type: "contact",
        target_id: contact.id,
        target_label: contact.full_name,
        metadata: %{
          "account_id" => contact.account_id,
          "event_id" => event.id,
          "path" => "/gtm/outreach/#{contact.id}",
          "queries" => Enum.map(searches, & &1.query),
          "research_type" => "person",
          "result_count" => Enum.sum(Enum.map(searches, &length(&1.results)))
        }
      }
    )
  end

  defp audit_page_research(contact, event, page) do
    Audit.record(
      "outreach.public_page_research_completed",
      %{
        target_type: "contact",
        target_id: contact.id,
        target_label: contact.full_name,
        metadata: %{
          "account_id" => contact.account_id,
          "event_id" => event.id,
          "path" => "/gtm/outreach/#{contact.id}",
          "truncated" => page.truncated,
          "url" => page.final_url
        }
      }
    )
  end

  defp normalize_count(count) when is_integer(count), do: count |> max(1) |> min(@maximum_count)
  defp normalize_count(_count), do: @default_count

  defp truncate(nil, _length), do: nil
  defp truncate(value, length) when is_binary(value), do: String.slice(value, 0, length)

  defp quoted(nil), do: nil
  defp quoted(value) when is_binary(value), do: ~s("#{String.trim(value)}")

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
end
