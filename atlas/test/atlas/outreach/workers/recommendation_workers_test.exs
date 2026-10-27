defmodule Atlas.Outreach.Workers.RecommendationWorkersTest do
  use Atlas.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Outreach.Recommendation
  alias Atlas.Outreach.RecommendationNotifier
  alias Atlas.Outreach.Workers.GenerateRecommendation
  alias Atlas.Outreach.Workers.NotifyRecommendation
  alias Atlas.Outreach.Workers.ScheduleRecommendations
  alias Atlas.Repo

  setup :verify_on_exit!

  test "periodic review schedules contacts with unreviewed timeline evidence" do
    {contact, _event} = insert_contact_with_event!()

    assert {:ok, 1} = ScheduleRecommendations.perform(%Oban.Job{})

    assert_enqueued(
      worker: GenerateRecommendation,
      args: %{"contact_id" => contact.id, "source" => "scheduled_review", "force" => false}
    )
  end

  test "notification delivery posts the suggestion and records the Slack message" do
    {contact, event} = insert_contact_with_event!()

    recommendation =
      %Recommendation{
        contact_id: contact.id,
        account_id: contact.account_id,
        source_event_id: event.id,
        slack_notification_requested_at: ~U[2026-07-20 10:05:00Z]
      }
      |> Recommendation.changeset(%{
        status: "pending",
        action_type: "research",
        recommended_event_kind: "note",
        title: "Find one relevant technical signal",
        guidance: "Read the team's latest engineering post.",
        rationale: "The timeline does not yet contain enough context for a message.",
        due_at: ~U[2026-07-21 09:00:00Z],
        confidence: Decimal.new("0.82"),
        evidence: %{"items" => [%{"event_id" => event.id, "observation" => event.title}]},
        generated_by_agent: "outreach_recommendation_agent"
      })
      |> Repo.insert!()

    expect(RecommendationNotifier, :notify, fn loaded ->
      assert loaded.id == recommendation.id
      assert loaded.contact.full_name == contact.full_name
      {:ok, %{channel_id: "C_SALES", thread_ts: "1717400000.000100"}}
    end)

    assert :ok =
             NotifyRecommendation.perform(%Oban.Job{args: %{"recommendation_id" => recommendation.id}})

    notified = Repo.get!(Recommendation, recommendation.id)
    assert notified.slack_notification_channel_id == "C_SALES"
    assert notified.slack_notification_thread_ts == "1717400000.000100"
    assert notified.slack_notification_posted_at
  end

  defp insert_contact_with_event! do
    account =
      %Account{}
      |> Account.changeset(%{
        account_key: "worker-outreach:#{System.unique_integer([:positive])}",
        name: "Acme Platforms",
        segment: :prospect
      })
      |> Repo.insert!()

    contact =
      %Contact{account_id: account.id}
      |> Contact.outreach_changeset(%{
        full_name: "Jordan #{System.unique_integer([:positive])}",
        email: "jordan-#{System.unique_integer([:positive])}@example.com",
        outreach_enrolled_at: ~U[2026-07-20 09:00:00Z]
      })
      |> Repo.insert!()

    event =
      %Event{account_id: account.id, contact_id: contact.id}
      |> Event.changeset(%{
        external_id: "worker-evidence-#{System.unique_integer([:positive])}",
        source: "atlas",
        kind: "enrolled",
        title: "Added to outreach",
        occurred_at: ~U[2026-07-20 09:00:00Z]
      })
      |> Repo.insert!()

    {contact, event}
  end
end
