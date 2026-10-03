defmodule Atlas.Outreach.RecommendationsTest do
  use Atlas.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Audit.Activity
  alias Atlas.Outreach
  alias Atlas.Outreach.Agents.RecommendationAgent
  alias Atlas.Outreach.MessageAttempt
  alias Atlas.Outreach.Recommendation
  alias Atlas.Outreach.Workers.GenerateRecommendation
  alias Atlas.Outreach.Workers.NotifyRecommendation
  alias Atlas.Repo
  alias Atlas.Users.User

  setup :verify_on_exit!

  test "persists one grounded recommendation and marks the contact checked" do
    {contact, event} = insert_contact_with_event!()

    expect(RecommendationAgent, :recommend, fn context ->
      assert context.contact.id == contact.id
      assert Enum.any?(context.events, &(&1.id == event.id))
      assert context.message_learning.total_evaluated == 0
      {:ok, generated_result(event)}
    end)

    assert {:ok, recommendation} = Outreach.generate_recommendation(contact.id)
    assert recommendation.action_type == "reply"
    assert recommendation.recommended_event_kind == "message_sent"
    assert recommendation.source_event_id == event.id
    assert recommendation.metadata["personalization_basis"] =~ "trust"
    assert recommendation.rationale == "Jordan offered a specific challenge, trust in build feedback."

    assert recommendation.draft_message ==
             "You mentioned trust, how does your team decide which feedback engineers will act on?"

    refute recommendation.rationale =~ "—"
    refute recommendation.draft_message =~ "—"
    assert Repo.get!(Contact, contact.id).outreach_recommendations_checked_at

    assert_enqueued(worker: NotifyRecommendation, args: %{"recommendation_id" => recommendation.id})

    assert %Activity{interface: "system"} =
             Repo.get_by!(Activity, action: "outreach.recommendation_generated", target_id: contact.id)
  end

  test "discards low-confidence or ungrounded output" do
    {contact, event} = insert_contact_with_event!()

    expect(RecommendationAgent, :recommend, fn _context ->
      result = generated_result(event)
      recommendation = result["recommendations"] |> hd() |> Map.put("confidence", "0.42")
      {:ok, %{"recommendations" => [recommendation]}}
    end)

    assert {:ok, nil} = Outreach.generate_recommendation(contact.id)
    assert Outreach.current_recommendation(contact) == nil
    assert Repo.get!(Contact, contact.id).outreach_recommendations_checked_at
  end

  test "accepts a connection request without an optional note" do
    {contact, event} = insert_contact_with_event!()

    expect(RecommendationAgent, :recommend, fn _context ->
      {:ok, connection_request_result(event, nil)}
    end)

    assert {:ok, recommendation} = Outreach.generate_recommendation(contact.id)
    assert recommendation.action_type == "connection_request"
    assert recommendation.recommended_event_kind == "connection_requested"
    assert recommendation.draft_message == nil
  end

  test "discards a connection request note over 200 characters" do
    {contact, event} = insert_contact_with_event!()

    expect(RecommendationAgent, :recommend, fn _context ->
      {:ok, connection_request_result(event, String.duplicate("a", 201))}
    end)

    assert {:ok, nil} = Outreach.generate_recommendation(contact.id)
    assert Outreach.current_recommendation(contact) == nil
  end

  test "persists an InMail with a short, relevant subject" do
    {contact, event} = insert_contact_with_event!()

    expect(RecommendationAgent, :recommend, fn _context ->
      {:ok, inmail_result(event, "Trust in build feedback")}
    end)

    assert {:ok, recommendation} = Outreach.generate_recommendation(contact.id)
    assert recommendation.action_type == "inmail"
    assert recommendation.recommended_event_kind == "message_sent"
    assert recommendation.draft_subject == "Trust in build feedback"
    assert recommendation.draft_message =~ "build feedback"
  end

  test "discards an InMail with a generic, identity-based subject" do
    {contact, event} = insert_contact_with_event!()

    expect(RecommendationAgent, :recommend, fn _context ->
      {:ok, inmail_result(event, "Connecting with Jordan Lee")}
    end)

    assert {:ok, nil} = Outreach.generate_recommendation(contact.id)
    assert Outreach.current_recommendation(contact) == nil
  end

  test "accepts research evidence recorded while the recommendation agent runs" do
    {contact, _event} = insert_contact_with_event!()

    expect(RecommendationAgent, :recommend, fn context ->
      research_event =
        %Event{account_id: contact.account_id, contact_id: contact.id}
        |> Event.changeset(%{
          external_id: "web-research-#{System.unique_integer([:positive])}",
          source: "web",
          kind: "research",
          title: "Public research for Jordan Lee",
          body: "Jordan wrote about trustworthy build feedback.",
          occurred_at: ~U[2026-07-21 10:00:00Z],
          url: "https://engineering.acme.example/build-feedback"
        })
        |> Repo.insert!()

      refute Enum.any?(context.events, &(&1.id == research_event.id))
      {:ok, generated_result(research_event)}
    end)

    assert {:ok, recommendation} = Outreach.generate_recommendation(contact.id)
    research_event = Repo.get_by!(Event, contact_id: contact.id, source: "web")
    assert recommendation.source_event_id == research_event.id
    assert recommendation.evidence["items"] |> hd() |> Map.fetch!("observation") =~ "Jordan wrote"
  end

  test "requests recommendation generation as a durable audited job" do
    actor = insert_user!()
    {contact, _event} = insert_contact_with_event!()

    assert {:ok, job} =
             Outreach.request_recommendation_generation(contact, actor, "dashboard")

    assert job.worker == inspect(GenerateRecommendation)
    assert job.args[:contact_id] == contact.id
    assert Outreach.recommendation_generation_pending?(contact)

    assert %Activity{actor_id: actor_id, metadata: metadata} =
             Repo.get_by!(Activity,
               action: "outreach.recommendation_requested",
               target_id: contact.id
             )

    assert actor_id == actor.id
    assert metadata["job_id"] == job.id
    assert metadata["source"] == "dashboard"

    job
    |> Ecto.Changeset.change(%{state: "completed"})
    |> Repo.update!()

    refute Outreach.recommendation_generation_pending?(contact)
  end

  test "generation status separates a finished run from one that never ran" do
    {contact, _event} = insert_contact_with_event!()

    assert Outreach.recommendation_generation_status(contact) == :none

    assert {:ok, job} = Outreach.request_recommendation_generation(contact)
    assert Outreach.recommendation_generation_status(contact) == :pending

    job
    |> Ecto.Changeset.change(%{state: "cancelled"})
    |> Repo.update!()

    assert Outreach.recommendation_generation_status(contact) == :failed

    job
    |> Ecto.Changeset.change(%{state: "completed"})
    |> Repo.update!()

    assert Outreach.recommendation_generation_status(contact) == :completed
  end

  test "a request collapsed into a pending job is not audited as a new request" do
    actor = insert_user!()
    {contact, _event} = insert_contact_with_event!()

    assert {:ok, job} = Outreach.request_recommendation_generation(contact, actor, "dashboard")
    assert {:ok, collapsed} = Outreach.request_recommendation_generation(contact, actor, "dashboard")

    assert collapsed.id == job.id

    assert [%Activity{metadata: metadata}] =
             Repo.all(from(activity in Activity, where: activity.action == "outreach.recommendation_requested"))

    assert metadata["job_id"] == job.id
  end

  test "new account evidence makes a checked outreach contact eligible again" do
    {contact, _event} = insert_contact_with_event!()
    checked_at = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

    contact
    |> Contact.outreach_recommendations_checked_changeset(%{outreach_recommendations_checked_at: checked_at})
    |> Repo.update!()

    assert contact.id in Outreach.list_recommendation_candidate_ids()

    from(event in Event, where: event.account_id == ^contact.account_id)
    |> Repo.update_all(set: [inserted_at: DateTime.to_naive(DateTime.add(checked_at, -60, :second))])

    Account
    |> Repo.get!(contact.account_id)
    |> Ecto.Changeset.change(%{updated_at: DateTime.to_naive(DateTime.add(checked_at, -60, :second))})
    |> Repo.update!()

    refute contact.id in Outreach.list_recommendation_candidate_ids()
  end

  test "completing a message suggestion records its draft and schedules another review" do
    actor = insert_user!()
    {contact, event} = insert_contact_with_event!()
    recommendation = insert_recommendation!(contact, event)

    assert {:ok, %{recommendation: completed, event: completion, contact: updated_contact}} =
             Outreach.complete_recommendation(recommendation, actor)

    assert completed.status == "completed"
    assert completed.reviewed_by_id == actor.id
    assert completion.kind == "message_sent"
    assert completion.body == recommendation.draft_message
    # The contact already replied, so sending a follow-up message must not
    # regress the pipeline stage back to "conversation_started".
    assert updated_contact.outreach_status == "replied"

    assert_enqueued(
      worker: GenerateRecommendation,
      args: %{"contact_id" => contact.id, "source" => "recommendation_completed", "force" => true}
    )

    assert %Activity{actor_id: actor_id} =
             Repo.get_by!(Activity, action: "outreach.recommendation_completed", target_id: recommendation.id)

    assert actor_id == actor.id
  end

  test "completing a stop suggestion retires the contact without scheduling another review" do
    actor = insert_user!()
    {contact, event} = insert_contact_with_event!()

    recommendation =
      insert_recommendation!(contact, event, %{
        action_type: "stop",
        recommended_event_kind: "note",
        title: "End outreach",
        guidance: "Do not contact Jordan again.",
        draft_message: nil
      })

    assert {:ok, %{event: completion, contact: updated_contact}} =
             Outreach.complete_recommendation(recommendation, actor)

    assert completion.kind == "note"
    assert completion.body =~ "End outreach"
    assert updated_contact.outreach_status == "not_interested"
    refute contact.id in Outreach.list_recommendation_candidate_ids()

    refute_enqueued(
      worker: GenerateRecommendation,
      args: %{"contact_id" => contact.id, "source" => "recommendation_completed", "force" => true}
    )
  end

  test "completing a connection request preserves its drafted note" do
    actor = insert_user!()
    {contact, event} = insert_contact_with_event!()

    recommendation =
      insert_recommendation!(contact, event, %{
        action_type: "connection_request",
        recommended_event_kind: "connection_requested",
        title: "Connect with Jordan",
        guidance: "Send a short connection note.",
        draft_message: "I appreciated your perspective on trustworthy build feedback."
      })

    sent_message = "I enjoyed your perspective on making build feedback trustworthy."

    assert {:ok, %{event: completion}} =
             Outreach.complete_recommendation(recommendation, actor, %{
               "sent_message" => sent_message
             })

    assert completion.kind == "connection_requested"
    assert completion.body == sent_message
    refute Map.has_key?(completion.metadata, "subject")
  end

  test "connection request completion without a sent message records the draft" do
    actor = insert_user!()
    {contact, event} = insert_contact_with_event!()

    recommendation =
      insert_recommendation!(contact, event, %{
        action_type: "connection_request",
        recommended_event_kind: "connection_requested",
        draft_message: "I appreciated your perspective on trustworthy build feedback."
      })

    assert {:ok, %{event: completion}} = Outreach.complete_recommendation(recommendation, actor)

    assert completion.kind == "connection_requested"
    assert completion.body == recommendation.draft_message
  end

  test "completing an InMail preserves its visible subject and learning data" do
    actor = insert_user!()
    {contact, event} = insert_contact_with_event!()

    recommendation =
      insert_recommendation!(contact, event, %{
        action_type: "inmail",
        recommended_event_kind: "message_sent",
        title: "Ask about trusted build feedback",
        guidance: "Send a concise InMail grounded in Jordan's concern.",
        draft_subject: "Trust in build feedback",
        draft_message: "How does your team decide which build feedback is trustworthy?"
      })

    sent_subject = "Making build feedback trustworthy"
    sent_message = "How are you deciding which build feedback engineers can trust today?"

    assert {:ok, %{event: completion}} =
             Outreach.complete_recommendation(recommendation, actor, %{
               "sent_subject" => sent_subject,
               "sent_message" => sent_message
             })

    assert completion.kind == "message_sent"
    assert completion.metadata["subject"] == sent_subject
    assert completion.body == sent_message

    attempt = Repo.get_by!(MessageAttempt, recommendation_id: recommendation.id)
    assert attempt.message_kind == "inmail"
    assert attempt.proposed_subject == recommendation.draft_subject
    assert attempt.sent_subject == sent_subject
  end

  test "dismissal keeps feedback for later agent runs" do
    actor = insert_user!()
    {contact, event} = insert_contact_with_event!()
    recommendation = insert_recommendation!(contact, event)

    assert {:ok, dismissed} =
             Outreach.dismiss_recommendation(recommendation, "Too generic for this role", actor)

    assert dismissed.status == "dismissed"
    assert dismissed.review_reason == "Too generic for this role"
    assert dismissed.reviewed_by_id == actor.id
    assert Outreach.current_recommendation(contact) == nil
  end

  defp insert_contact_with_event! do
    account =
      %Account{}
      |> Account.changeset(%{
        account_key: "outreach-guidance:#{System.unique_integer([:positive])}",
        name: "Acme Platforms",
        primary_domain: "acme.example",
        segment: :prospect
      })
      |> Repo.insert!()

    contact =
      %Contact{account_id: account.id}
      |> Contact.outreach_changeset(%{
        full_name: "Jordan Lee",
        email: "jordan-#{System.unique_integer([:positive])}@example.com",
        title: "Director of Developer Productivity",
        linkedin_url: "https://www.linkedin.com/in/jordan-#{System.unique_integer([:positive])}",
        outreach_enrolled_at: ~U[2026-07-20 09:00:00Z],
        outreach_status: "replied"
      })
      |> Repo.insert!()

    event =
      %Event{account_id: account.id, contact_id: contact.id}
      |> Event.changeset(%{
        external_id: "reply-#{System.unique_integer([:positive])}",
        source: "linkedin",
        kind: "message_received",
        title: "Message received",
        body: "The hard part is helping teams trust build feedback enough to act on it.",
        occurred_at: ~U[2026-07-20 10:00:00Z]
      })
      |> Repo.insert!()

    {contact, event}
  end

  defp insert_recommendation!(contact, event, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          status: "pending",
          action_type: "reply",
          recommended_event_kind: "message_sent",
          title: "Explore how the team builds trust",
          guidance: "Reflect the concern and ask one question.",
          rationale: "Jordan offered a specific challenge.",
          draft_message: "How does your team decide which feedback engineers will trust?",
          due_at: ~U[2026-07-20 12:00:00Z],
          confidence: Decimal.new("0.91"),
          evidence: %{"items" => [%{"event_id" => event.id, "observation" => event.body}]},
          generated_by_agent: "outreach_recommendation_agent"
        },
        overrides
      )

    %Recommendation{contact_id: contact.id, account_id: contact.account_id, source_event_id: event.id}
    |> Recommendation.changeset(attrs)
    |> Repo.insert!()
  end

  defp generated_result(event) do
    %{
      "recommendations" => [
        %{
          "action_type" => "reply",
          "title" => "Explore how the team builds trust",
          "guidance" => "Reflect the concern and ask one question.",
          "rationale" => "Jordan offered a specific challenge — trust in build feedback.",
          "draft_message" => "You mentioned trust — how does your team decide which feedback engineers will act on?",
          "due_in_days" => 0,
          "confidence" => "0.91",
          "personalization_basis" => "Jordan's reply about trust",
          "message_intent" => "deepen_context",
          "personalization_source" => "recipient_message",
          "call_to_action" => "question",
          "risks" => ["Do not pitch."],
          "evidence" => [%{"event_id" => event.id, "observation" => event.body}]
        }
      ]
    }
  end

  defp connection_request_result(event, draft_message) do
    recommendation = %{
      "action_type" => "connection_request",
      "title" => "Connect with Jordan",
      "guidance" => "Send a connection request without a sales pitch.",
      "rationale" => "Jordan's role is relevant to the observed work.",
      "due_in_days" => 0,
      "confidence" => "0.91",
      "personalization_basis" => "Jordan's role",
      "risks" => ["Do not pitch."],
      "evidence" => [%{"event_id" => event.id, "observation" => event.body}]
    }

    recommendation =
      if draft_message do
        Map.put(recommendation, "draft_message", draft_message)
      else
        recommendation
      end

    %{"recommendations" => [recommendation]}
  end

  defp inmail_result(event, subject) do
    %{
      "recommendations" => [
        %{
          "action_type" => "inmail",
          "title" => "Ask about trusted build feedback",
          "guidance" => "Send a concise InMail grounded in Jordan's concern.",
          "rationale" => "Jordan described a specific engineering outcome.",
          "draft_subject" => subject,
          "draft_message" => "How does your team decide which build feedback engineers can trust?",
          "due_in_days" => 0,
          "confidence" => "0.91",
          "personalization_basis" => "Jordan's comment about build feedback",
          "message_intent" => "understand_problem",
          "personalization_source" => "recipient_message",
          "call_to_action" => "question",
          "risks" => ["Do not pitch."],
          "evidence" => [%{"event_id" => event.id, "observation" => event.body}]
        }
      ]
    }
  end

  defp insert_user! do
    %User{}
    |> User.changeset(%{
      email: "reviewer-#{System.unique_integer([:positive])}@tuist.dev",
      name: "Outreach Reviewer"
    })
    |> Repo.insert!()
  end
end
