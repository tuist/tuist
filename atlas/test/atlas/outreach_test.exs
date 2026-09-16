defmodule Atlas.OutreachTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Audit.Activity
  alias Atlas.GTM.Opportunity
  alias Atlas.GTM.OpportunityContact
  alias Atlas.Outreach
  alias Atlas.Outreach.Candidate
  alias Atlas.Outreach.MessageAttempt
  alias Atlas.Users.User

  test "searches Apollo into Atlas-owned candidates without creating contacts or accounts" do
    actor = insert_user!()

    request = fn opts ->
      case opts[:url] do
        "https://api.apollo.io/api/v1/mixed_companies/search" ->
          {:ok,
           %{
             status: 200,
             body: %{
               "organizations" => [
                 %{
                   "id" => "apollo-account-1",
                   "name" => "Search Platforms",
                   "primary_domain" => "search.example",
                   "naics_codes" => ["522320"]
                 }
               ]
             }
           }}

        "https://api.apollo.io/api/v1/mixed_people/api_search" ->
          {:ok,
           %{
             status: 200,
             body: %{
               "people" => [
                 %{
                   "id" => "search-person-1",
                   "name" => "Riley Stone",
                   "title" => "Head of Mobile",
                   "organization_id" => "apollo-account-1",
                   "linkedin_url" => "https://www.linkedin.com/in/riley-stone",
                   "country" => "United States"
                 }
               ],
               "pagination" => %{"total_entries" => 1461}
             }
           }}
      end
    end

    opts = [api_key: "apollo-key", request: request, segments: ["mobile_mid_large"]]

    assert {:ok, %{created: 1, updated: 0, returned: 1, total_matches: 1461}} =
             Outreach.search_apollo(actor, opts)

    candidate = Repo.get_by!(Candidate, source: "apollo", source_id: "search-person-1")

    assert candidate.full_name == "Riley Stone"
    assert candidate.status == "pending"
    assert candidate.organization_name == "Search Platforms"
    assert candidate.organization_domain == "search.example"
    assert candidate.metadata["country"] == "United States"
    assert candidate.metadata["search_definition"]["organization_locations"] == nil
    assert %DateTime{} = candidate.slack_notification_requested_at
    assert candidate.slack_notification_posted_at == nil
    assert Repo.aggregate(Contact, :count) == 0
    assert Repo.aggregate(Account, :count) == 0
    assert Repo.aggregate(Event, :count) == 0

    assert %Activity{actor_id: actor_id} = Repo.get_by!(Activity, action: "outreach.apollo_searched")

    assert actor_id == actor.id

    assert {:ok, %{created: 0, updated: 1}} = Outreach.search_apollo(actor, opts)
    assert Repo.aggregate(Candidate, :count) == 1
    assert Repo.aggregate(Contact, :count) == 0

    assert Repo.get!(Candidate, candidate.id).slack_notification_requested_at ==
             candidate.slack_notification_requested_at
  end

  test "tracks candidates waiting for their sales notification" do
    candidate =
      %Candidate{slack_notification_requested_at: ~U[2026-07-20 12:00:00Z]}
      |> Candidate.changeset(candidate_attrs())
      |> Repo.insert!()

    assert [pending] = Outreach.list_candidates_pending_notification()
    assert pending.id == candidate.id

    assert {:ok, notified} =
             Outreach.mark_candidate_notified(candidate, %{
               channel_id: "C_SALES",
               thread_ts: "1717400000.000100"
             })

    assert %DateTime{} = notified.slack_notification_posted_at
    assert Outreach.list_candidates_pending_notification() == []

    assert %Activity{interface: "system"} =
             Repo.get_by!(Activity, action: "outreach.candidate_notified", target_id: candidate.id)
  end

  test "enrolls an Atlas candidate explicitly and records its provenance" do
    actor = insert_user!()
    candidate = insert_candidate!()

    assert {:ok, contact} = Outreach.enroll_candidate(candidate, actor)

    assert contact.full_name == "Riley Stone"
    assert contact.account.name == "Search Platforms"
    assert contact.account.primary_domain == "search.example"
    assert contact.source_id == candidate.source_id
    assert contact.metadata["outreach_candidate_id"] == candidate.id

    enrolled = Repo.get!(Candidate, candidate.id)
    assert enrolled.status == "enrolled"
    assert enrolled.contact_id == contact.id
    assert %DateTime{} = enrolled.reviewed_at

    assert [%Event{external_id: external_id, kind: "enrolled"}] = contact.events
    assert external_id == "outreach-candidate-enrollment:#{candidate.id}"

    assert %Activity{actor_id: actor_id} =
             Repo.get_by!(Activity, action: "outreach.candidate_enrolled", target_id: contact.id)

    assert actor_id == actor.id
    assert Outreach.recommendation_generation_pending?(contact)

    assert {:ok, same_contact} = Outreach.enroll_candidate(enrolled, actor)
    assert same_contact.id == contact.id
    assert Repo.aggregate(Contact, :count) == 1
    assert Repo.aggregate(Event, :count) == 1
  end

  test "rejects an Atlas candidate without creating a contact" do
    actor = insert_user!()
    candidate = insert_candidate!()

    assert {:ok, rejected} = Outreach.reject_candidate(candidate, "Mobile networks role", actor)

    assert rejected.status == "rejected"
    assert rejected.rejection_reason == "Mobile networks role"
    assert %DateTime{} = rejected.reviewed_at
    assert Repo.aggregate(Contact, :count) == 0

    assert %Activity{actor_id: actor_id} =
             Repo.get_by!(Activity, action: "outreach.candidate_rejected", target_id: candidate.id)

    assert actor_id == actor.id
  end

  test "promotes an Apollo suggestion into the account contact and records enrollment" do
    actor = insert_user!()
    suggestion = insert_suggestion!()

    assert {:ok, contact} = Outreach.enroll_opportunity_contact(suggestion, actor)

    assert contact.full_name == "Jordan Lee"
    assert contact.account.name == "Acme Platforms"
    assert contact.account.segment == :prospect
    assert contact.source == "apollo"
    assert contact.source_id == "apollo-person-1"
    assert contact.linkedin_url == "https://www.linkedin.com/in/jordan-lee"
    assert contact.outreach_status == "not_contacted"
    assert %DateTime{} = contact.outreach_enrolled_at

    assert [%Event{kind: "enrolled", source: "apollo", contact_id: contact_id}] = contact.events
    assert contact_id == contact.id

    assert %Activity{interface: "system", actor_id: actor_id} =
             Repo.get_by!(Activity, action: "outreach.contact_enrolled", target_id: contact.id)

    assert actor_id == actor.id
    assert Repo.get!(Account, contact.account_id).contacts_count == 1
    assert Outreach.recommendation_generation_pending?(contact)
  end

  test "enrollment is idempotent for the same Apollo person" do
    suggestion = insert_suggestion!()

    assert {:ok, first} = Outreach.enroll_opportunity_contact(suggestion)
    assert {:ok, second} = Outreach.enroll_opportunity_contact(suggestion)

    assert first.id == second.id
    assert Repo.aggregate(Contact, :count) == 1
    assert Repo.aggregate(from(event in Event, where: event.contact_id == ^first.id), :count) == 1
  end

  test "records a linear LinkedIn history and advances the outreach stage" do
    actor = insert_user!()
    suggestion = insert_suggestion!()
    {:ok, contact} = Outreach.enroll_opportunity_contact(suggestion, actor)
    enrolled_at = contact.outreach_enrolled_at
    request_at = DateTime.add(enrolled_at, 1, :hour)
    accepted_at = DateTime.add(enrolled_at, 2, :hour)
    message_at = DateTime.add(enrolled_at, 3, :hour)
    reply_at = DateTime.add(enrolled_at, 4, :hour)

    assert {:ok, request, contact} =
             Outreach.record_event(
               contact,
               %{kind: "connection_requested", occurred_at: request_at},
               actor
             )

    assert request.title == "Connection request sent"
    assert contact.outreach_status == "connection_requested"

    assert {:ok, _accepted, contact} =
             Outreach.record_event(
               contact,
               %{kind: "connection_accepted", occurred_at: accepted_at},
               actor
             )

    assert contact.outreach_status == "connected"

    assert {:ok, message, contact} =
             Outreach.record_event(
               contact,
               %{
                 kind: "message_sent",
                 body: "What has been hardest about keeping build feedback useful?",
                 occurred_at: message_at
               },
               actor
             )

    assert message.body == "What has been hardest about keeping build feedback useful?"
    assert contact.outreach_status == "conversation_started"

    attempt = Repo.get_by!(MessageAttempt, sent_event_id: message.id)
    assert attempt.sent_message == message.body
    assert attempt.outcome == "pending"

    assert {:ok, reply, contact} =
             Outreach.record_event(
               contact,
               %{
                 kind: "message_received",
                 body: "Helping teams trust the feedback.",
                 occurred_at: reply_at
               },
               actor
             )

    assert reply.source == "linkedin"
    assert contact.outreach_status == "replied"
    assert Repo.get!(MessageAttempt, attempt.id).outcome == "replied"
    assert Repo.get!(MessageAttempt, attempt.id).response_event_id == reply.id
    # The reply is inbound, so our last outreach timestamp stays at the
    # message we sent rather than advancing to when they replied.
    assert contact.last_outreach_at == message_at

    assert Enum.map(contact.events, & &1.kind) == [
             "message_received",
             "message_sent",
             "connection_accepted",
             "connection_requested",
             "enrolled"
           ]
  end

  test "classifies a received message so later recommendations can learn from its outcome" do
    suggestion = insert_suggestion!()
    {:ok, contact} = Outreach.enroll_opportunity_contact(suggestion)

    assert {:ok, sent, contact} =
             Outreach.record_event(contact, %{
               kind: "message_sent",
               body: "How are you approaching build feedback today?",
               occurred_at: ~U[2026-07-20 10:00:00Z]
             })

    assert {:ok, reply, contact} =
             Outreach.record_event(contact, %{
               kind: "message_received",
               body: "This is timely. I would like to compare approaches.",
               response_outcome: "positive_reply",
               occurred_at: ~U[2026-07-20 11:00:00Z]
             })

    assert contact.outreach_status == "interested"
    assert reply.metadata["response_outcome"] == "positive_reply"

    attempt = Repo.get_by!(MessageAttempt, sent_event_id: sent.id)
    assert attempt.outcome == "positive_reply"
    assert attempt.response_event_id == reply.id
    assert attempt.outcome_at == reply.occurred_at
  end

  test "does not revive a contact after they have been classified as not interested" do
    suggestion = insert_suggestion!()
    {:ok, contact} = Outreach.enroll_opportunity_contact(suggestion)

    assert {:ok, _event, contact} =
             Outreach.record_event(contact, %{
               kind: "message_received",
               body: "Please do not follow up.",
               response_outcome: "not_interested",
               occurred_at: ~U[2026-07-20 11:00:00Z]
             })

    assert {:ok, _event, contact} =
             Outreach.record_event(contact, %{
               kind: "message_received",
               body: "An older positive reply recorded later.",
               response_outcome: "positive_reply",
               occurred_at: ~U[2026-07-20 10:00:00Z]
             })

    assert contact.outreach_status == "not_interested"
  end

  test "requires message text and lists enrolled contacts through Flop pagination" do
    suggestion = insert_suggestion!()
    {:ok, contact} = Outreach.enroll_opportunity_contact(suggestion)

    assert {:error, changeset} = Outreach.record_event(contact, %{kind: "message_sent"})
    assert %{body: ["can't be blank"]} = errors_on(changeset)

    {contacts, meta} = Outreach.list_contacts(query: "Acme", status: "not_contacted", limit: 10)

    assert [listed] = contacts
    assert listed.id == contact.id
    assert listed.account.name == "Acme Platforms"
    assert meta.total_count == 1
  end

  defp insert_suggestion! do
    opportunity =
      %Opportunity{}
      |> Opportunity.changeset(%{
        company_key: "domain:acme-#{System.unique_integer([:positive])}.example",
        company_name: "Acme Platforms",
        domain: "acme-#{System.unique_integer([:positive])}.example",
        status: "new",
        score: 82
      })
      |> Repo.insert!()

    %OpportunityContact{opportunity_id: opportunity.id}
    |> OpportunityContact.changeset(%{
      source: "apollo",
      full_name: "Jordan Lee",
      title: "Director of Developer Productivity",
      organization_name: "Acme Platforms",
      linkedin_url: "https://www.linkedin.com/in/jordan-lee",
      email: nil,
      confidence: 95,
      metadata: %{"apollo_id" => "apollo-person-1"}
    })
    |> Repo.insert!()
  end

  defp insert_user! do
    %User{}
    |> User.changeset(%{
      email: "outreach-#{System.unique_integer([:positive])}@tuist.dev",
      name: "Outreach User"
    })
    |> Repo.insert!()
  end

  defp insert_candidate! do
    %Candidate{}
    |> Candidate.changeset(candidate_attrs())
    |> Repo.insert!()
  end

  defp candidate_attrs do
    %{
      source: "apollo",
      source_id: "apollo-candidate-#{System.unique_integer([:positive])}",
      search_segment: "mobile_mid_large",
      search_version: 1,
      status: "pending",
      full_name: "Riley Stone",
      title: "Head of Mobile",
      organization_name: "Search Platforms",
      organization_source_id: "apollo-account-1",
      organization_domain: "search.example",
      linkedin_url: "https://www.linkedin.com/in/riley-stone",
      search_rank: 1,
      discovered_at: ~U[2026-07-20 12:00:00Z],
      metadata: %{"country" => "United States", "confidence" => 86}
    }
  end
end
