defmodule Atlas.SearchTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.Outcome
  alias Atlas.GTM.BlogPostIdea
  alias Atlas.GTM.Opportunity
  alias Atlas.GTM.SocialChannelIdea
  alias Atlas.GTM.SocialPostRevision
  alias Atlas.Repo
  alias Atlas.Search
  alias Atlas.Search.Record
  alias Atlas.Vector

  setup :verify_on_exit!

  test "indexes prose-heavy records and searches them with full-text fallback" do
    stub(Vector, :configured?, fn -> false end)

    account = insert_account!(%{name: "Acme Labs"})
    event = insert_event!(account, %{title: "Security review", body: "Customer asked for SOC2 evidence."})

    outcome =
      insert_outcome!(account, %{
        title: "Complete the security evaluation",
        description: "Share the SOC2 report and reach written approval."
      })

    idea = insert_blog_post_idea!(%{title: "Remote cache economics", description: "Explain build cost reduction."})

    social_idea =
      insert_social_channel_idea!(%{
        title: "Cache chart social post",
        description: "Share build minute savings."
      })

    insert_social_post_revision!(social_idea, %{
      body: "Use the launch hook about recovered developer waiting time."
    })

    social_idea = Repo.preload(social_idea, :post_revisions)

    opportunity = insert_opportunity!(%{company_name: "Build Corp", signal_summary: "Large CI fleet migration."})

    assert {:ok, _record} = Search.index_account_event(event)
    assert {:ok, _record} = Search.index_account_outcome(outcome)
    assert {:ok, _record} = Search.index_blog_post_idea(idea)
    assert {:ok, _record} = Search.index_social_channel_idea(social_idea)
    assert {:ok, _record} = Search.index_gtm_opportunity(opportunity)

    assert {:ok, results} = Search.search("SOC2 security", limit: 5)

    assert Enum.any?(results, &(&1.source_type == "account_event" and &1.source_id == event.id))
    assert Enum.any?(results, &(&1.source_type == "account_outcome" and &1.source_id == outcome.id))
    assert Enum.all?(results, &(&1.account_name == "Acme Labs"))

    assert {:ok, [blog_result]} = Search.search("build cost reduction", source_types: ["blog_post_idea"])
    assert blog_result.source_id == idea.id

    assert {:ok, [social_result]} = Search.search("build minute", source_types: ["social_channel_idea"])
    assert social_result.source_id == social_idea.id

    assert {:ok, [revision_result]} = Search.search("launch hook", source_types: ["social_channel_idea"])
    assert revision_result.source_id == social_idea.id

    assert {:ok, [opportunity_result]} = Search.search("fleet migration", source_types: ["gtm_opportunity"])
    assert opportunity_result.source_id == opportunity.id
  end

  test "filters search records by account" do
    stub(Vector, :configured?, fn -> false end)

    target = insert_account!(%{name: "Target"})
    other = insert_account!(%{name: "Other"})

    target_event = insert_event!(target, %{title: "Procurement", body: "Security procurement follow-up."})
    other_event = insert_event!(other, %{title: "Procurement", body: "Security procurement follow-up."})

    Search.index_account_event(target_event)
    Search.index_account_event(other_event)

    assert {:ok, [result]} = Search.search("procurement", account_id: target.id)
    assert result.source_id == target_event.id
    assert result.account_id == target.id
  end

  test "does not cast account_id through the public search record changeset" do
    account = insert_account!(%{name: "Tenant"})

    changeset =
      Record.changeset(%Record{}, %{
        "source_type" => "account_event",
        "source_id" => Ecto.UUID.generate(),
        "account_id" => account.id,
        "title" => "Tenant event"
      })

    refute Ecto.Changeset.get_change(changeset, :account_id)
  end

  test "sets account_id explicitly through the search context" do
    stub(Vector, :configured?, fn -> false end)

    account = insert_account!(%{name: "Context Tenant"})

    assert {:ok, record} =
             Search.upsert_record(%{
               source_type: "account_event",
               source_id: Ecto.UUID.generate(),
               account_id: account.id,
               title: "Tenant event"
             })

    assert record.account_id == account.id
  end

  test "hydrates vector results from Postgres" do
    stub(Vector, :configured?, fn -> true end)

    {:ok, record} =
      Search.upsert_record(
        %{
          source_type: "blog_post_idea",
          source_id: Ecto.UUID.generate(),
          title: "Remote cache economics",
          body: "Explain build cost reduction.",
          path: "/gtm/content/example"
        },
        embed?: false
      )

    stub(Vector, :search, fn _embedding, opts ->
      assert opts[:filter] == %{"eq" => %{"field" => "source_type", "value" => "atlas_search_record"}}
      {:ok, %{"results" => [%{"vector" => %{"id" => "search_record:#{record.id}"}, "score" => 0.92}]}}
    end)

    # `hybrid_search/3` runs the vector lookup in a task and brutal-kills it after
    # `vector_timeout`, falling back to the full-text half. Nothing in this record
    # matches "build farm spend" by text, so on a loaded scheduler the default
    # second is enough to lose the task and the whole result with it. The stub
    # answers immediately, so a generous timeout only costs time when the code is
    # actually broken.
    assert {:ok, [result]} = Search.search("build farm spend", limit: 1, vector_timeout: :timer.seconds(30))
    assert result.id == record.id
    assert result.score > 0
  end

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :lead
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_event!(account, attrs) do
    defaults = %{
      external_id: "event:#{System.unique_integer([:positive])}",
      source: "atlas",
      kind: "note",
      title: "Event",
      occurred_at: ~U[2026-01-01 00:00:00Z],
      account_id: account.id
    }

    %Event{}
    |> Event.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_outcome!(account, attrs) do
    defaults = %{title: "Customer outcome", status: "active", health: "on_track", motion: "evaluation"}

    %Outcome{account_id: account.id}
    |> Outcome.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_blog_post_idea!(attrs) do
    defaults = %{title: "Idea", status: "idea"}

    %BlogPostIdea{}
    |> BlogPostIdea.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_social_channel_idea!(attrs) do
    defaults = %{title: "Social idea", status: "idea"}

    %SocialChannelIdea{}
    |> SocialChannelIdea.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_social_post_revision!(idea, attrs) do
    defaults = %{body: "Social post body", status: "draft"}

    %SocialPostRevision{social_channel_idea_id: idea.id, revision_number: 1}
    |> SocialPostRevision.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_opportunity!(attrs) do
    defaults = %{
      company_key: "company:#{System.unique_integer([:positive])}",
      company_name: "Company",
      status: "new",
      score: 10
    }

    %Opportunity{}
    |> Opportunity.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
