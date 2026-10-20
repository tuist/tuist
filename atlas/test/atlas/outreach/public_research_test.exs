defmodule Atlas.Outreach.PublicResearchTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Audit
  alias Atlas.Audit.Activity
  alias Atlas.MCP.Tools.SearchWeb
  alias Atlas.Outreach.PublicResearch
  alias Atlas.Repo
  alias Atlas.Search.Record
  alias Atlas.Slack.URLContent

  setup :verify_on_exit!

  test "records public search results as auditable timeline evidence" do
    contact = insert_contact!()
    query = ~s("Jordan Lee" "Acme Platforms" developer productivity)

    expect(SearchWeb, :execute, fn nil, %{"query" => ^query, "count" => 5} ->
      {:ok,
       %{
         query: query,
         count: 5,
         results: [
           %{
             title: "How Acme improves build feedback",
             url: "https://engineering.acme.example/build-feedback",
             snippet: "Jordan Lee explains how Acme makes build feedback easier to trust.",
             age: "2 months ago"
           }
         ]
       }}
    end)

    result =
      Audit.with_context(%{interface: "worker"}, fn ->
        PublicResearch.search(contact, %{"query" => query})
      end)

    assert {:ok, %{event_id: event_id, query: ^query, results: [_result]}} = result

    event = Repo.get!(Event, event_id)
    assert event.account_id == contact.account_id
    assert event.contact_id == contact.id
    assert event.source == "web"
    assert event.kind == "research"
    assert event.url == "https://engineering.acme.example/build-feedback"
    assert event.body =~ "Jordan Lee explains"
    assert event.metadata["query"] == query
    assert event.metadata["result_count"] == 1

    assert Repo.get_by!(Record, source_type: "account_event", source_id: event.id)

    assert %Activity{interface: "worker", metadata: metadata} =
             Repo.get_by!(Activity,
               action: "outreach.public_research_completed",
               target_id: contact.id
             )

    assert metadata["event_id"] == event.id
    assert metadata["path"] == "/commercial/gtm/outreach/#{contact.id}"
  end

  test "researches identity, company, GitHub, and authored public sources together" do
    contact = insert_contact!()

    expect(SearchWeb, :execute, 4, fn nil, %{"query" => query, "count" => 5} ->
      {title, url} =
        cond do
          String.contains?(query, "site:acme.example") ->
            {"Jordan Lee at Acme", "https://acme.example/people/jordan"}

          String.contains?(query, "site:github.com") ->
            {"Jordan Lee · GitHub", "https://github.com/jordanlee"}

          String.contains?(query, "blog OR podcast") ->
            {"Jordan's build systems talk", "https://jordan.example/talks/build-systems"}

          true ->
            {"Jordan Lee, Director of Developer Productivity", "https://directory.example/jordan-lee"}
        end

      {:ok,
       %{
         query: query,
         count: 5,
         results: [
           %{
             title: title,
             url: url,
             snippet: "Jordan writes about <strong>trustworthy build feedback</strong>.",
             age: nil
           }
         ]
       }}
    end)

    result =
      Audit.with_context(%{interface: "worker"}, fn ->
        PublicResearch.research_person(contact)
      end)

    assert {:ok, %{event_id: event_id, searches: searches}} = result
    assert Enum.map(searches, & &1.source) == ~w(identity company github authored)

    event = Repo.get!(Event, event_id)
    assert event.title == "Public profile research for Jordan Lee"
    assert event.body =~ "## Sources searched"
    assert event.body =~ "### GitHub profiles and public work"
    assert event.body =~ "https://github.com/jordanlee"
    assert event.body =~ "### Personal sites and authored work"
    assert event.metadata["research_type"] == "person"
    assert event.metadata["result_count"] == 4
    assert Enum.map(event.metadata["results"], & &1["source"]) == ~w(identity company github authored)

    assert %Activity{interface: "worker", metadata: metadata} =
             Repo.get_by!(Activity,
               action: "outreach.public_research_completed",
               target_id: contact.id
             )

    assert metadata["research_type"] == "person"
    assert length(metadata["queries"]) == 4
  end

  test "reads and records a public profile page as auditable evidence" do
    contact = insert_contact!()
    url = "https://github.com/jordanlee"

    expect(URLContent, :fetch, fn ^url ->
      {:ok,
       %{
         final_url: url,
         content_type: "text/html",
         title: "Jordan Lee · GitHub",
         content: "Jordan maintains tools for trustworthy build feedback.",
         truncated: false,
         redirects_followed: 0
       }}
    end)

    result =
      Audit.with_context(%{interface: "worker"}, fn ->
        PublicResearch.read_page(contact, %{"url" => url})
      end)

    assert {:ok, %{event_id: event_id, url: ^url, truncated: false}} = result

    event = Repo.get!(Event, event_id)
    assert event.title == "Jordan Lee · GitHub"
    assert event.url == url
    assert event.body =~ "Jordan maintains tools"
    assert event.metadata["research_type"] == "public_page"

    assert %Activity{interface: "worker", metadata: metadata} =
             Repo.get_by!(Activity,
               action: "outreach.public_page_research_completed",
               target_id: contact.id
             )

    assert metadata["url"] == url
    assert metadata["path"] == "/commercial/gtm/outreach/#{contact.id}"
  end

  defp insert_contact! do
    account =
      %Account{}
      |> Account.changeset(%{
        account_key: "public-research:#{System.unique_integer([:positive])}",
        name: "Acme Platforms",
        primary_domain: "acme.example",
        segment: :prospect
      })
      |> Repo.insert!()

    %Contact{account_id: account.id}
    |> Contact.outreach_changeset(%{
      full_name: "Jordan Lee",
      email: "jordan.lee@acme.example",
      title: "Director of Developer Productivity",
      outreach_enrolled_at: ~U[2026-07-20 09:00:00Z]
    })
    |> Repo.insert!()
  end
end
