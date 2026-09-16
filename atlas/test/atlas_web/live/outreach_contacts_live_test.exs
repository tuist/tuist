defmodule AtlasWeb.OutreachContactsLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Outreach
  alias Atlas.Outreach.Candidate
  alias Atlas.Outreach.MessageAttempt
  alias Atlas.Outreach.Recommendation
  alias Atlas.Repo
  alias Atlas.TestSupport.ScreenshotNoteAgent
  alias AtlasWeb.Utilities.Avatar

  test "renders empty outreach states inside their tables", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "outreach-empty@tuist.dev"})

    {:ok, view, _html} = live(conn, ~p"/gtm/outreach")

    assert has_element?(
             view,
             "#outreach-candidates-empty-table.noora-table .noora-table-empty-state"
           )

    assert has_element?(
             view,
             "#outreach-contacts-empty-table.noora-table .noora-table-empty-state"
           )
  end

  test "lists outreach contacts and opens their detail history", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "outreach-list@tuist.dev"})
    contact = insert_contact!()

    {:ok, _event, contact} =
      Outreach.record_event(contact, %{
        kind: "connection_requested",
        occurred_at: ~U[2026-07-18 09:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/gtm/outreach")

    assert has_element?(view, "#gtm-outreach")
    assert has_element?(view, "#gtm-outreach h1", "Outreach")
    assert has_element?(view, "#outreach-contact-search-form")
    assert has_element?(view, "#outreach-contacts-table")
    refute has_element?(view, "#search-apollo-candidates")
    refute has_element?(view, "#gtm-outreach", "Apollo candidates")

    assert has_element?(
             view,
             ~s(#outreach-contact-avatar-#{contact.id} img[src="#{Avatar.gravatar_url(contact.email)}"])
           )

    assert has_element?(
             view,
             ~s(#outreach-contacts-table a[href="/gtm/outreach/#{contact.id}"])
           )

    {:ok, detail, _html} = live(conn, ~p"/gtm/outreach/#{contact.id}")

    assert has_element?(detail, "#outreach-contact")
    assert has_element?(detail, "#outreach-contact-events", "Connection request sent")

    assert has_element?(
             detail,
             "[data-part='next-step-card']",
             "Next step"
           )

    assert has_element?(detail, "#generate-outreach-recommendation")
    assert has_element?(detail, "#generate-outreach-recommendation", "Research person")
    assert has_element?(detail, "[data-part='recommendation-empty']", "personal sites")
    assert has_element?(detail, "[data-part='recommendation-empty-icon']")
    assert has_element?(detail, "#outreach-event-form")
    assert has_element?(detail, "#outreach-event-response-outcome")
    assert has_element?(detail, "#outreach-contact-linkedin")
    assert has_element?(detail, ~s(#outreach-contact img[src="#{Avatar.gravatar_url(contact.email)}"]))
    refute has_element?(detail, "#outreach-contact-back")
    refute has_element?(detail, "[data-part='contact-actions']", "Connection sent")
  end

  test "renders history bodies as sanitized Markdown", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "outreach-markdown@tuist.dev"})
    contact = insert_contact!()

    %Event{account_id: contact.account_id, contact_id: contact.id}
    |> Event.changeset(%{
      external_id: "markdown-#{System.unique_integer([:positive])}",
      source: "web",
      kind: "research",
      title: "Public profile research for Jordan Lee",
      body: """
      ## Profiles

      - **GitHub:** [Jordan's public work](https://github.com/jordanlee)
      - Jordan writes about <strong>trustworthy build feedback</strong>.

      <script>window.bad = true</script>
      """,
      occurred_at: ~U[2026-07-21 10:00:00Z]
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/gtm/outreach/#{contact.id}")

    assert has_element?(view, "[data-part='event-body'] h2", "Profiles")
    assert has_element?(view, "[data-part='event-body'] ul li strong", "GitHub:")

    assert has_element?(
             view,
             "[data-part='event-body'] a[href='https://github.com/jordanlee']",
             "Jordan's public work"
           )

    assert has_element?(view, "[data-part='event-body'] strong", "trustworthy build feedback")
    refute render(view) =~ "<script>"
    refute render(view) =~ "&lt;strong&gt;"
  end

  test "keeps preparing the next step after the page is refreshed", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "outreach-refresh@tuist.dev"})
    contact = insert_contact!()

    {:ok, view, _html} = live(conn, ~p"/gtm/outreach/#{contact.id}")

    view
    |> element("#generate-outreach-recommendation")
    |> render_click()

    assert has_element?(view, "#outreach-recommendation-processing")
    assert Outreach.recommendation_generation_pending?(contact)

    {:ok, refreshed, _html} = live(conn, ~p"/gtm/outreach/#{contact.id}")

    assert has_element?(refreshed, "#outreach-recommendation-processing")
    refute has_element?(refreshed, "#outreach-recommendation-empty")
    refute has_element?(refreshed, "#generate-outreach-recommendation")

    # Settle the job so neither view keeps polling once the test connection goes away.
    cancel_generation_job!(contact)
    send(view.pid, :poll_recommendation)
    send(refreshed.pid, :poll_recommendation)
    refute has_element?(refreshed, "#outreach-recommendation-processing")
  end

  test "reports a failed generation as an error rather than missing evidence", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "outreach-failed-generation@tuist.dev"})
    contact = insert_contact!()

    {:ok, view, _html} = live(conn, ~p"/gtm/outreach/#{contact.id}")

    view
    |> element("#generate-outreach-recommendation")
    |> render_click()

    cancel_generation_job!(contact)
    send(view.pid, :poll_recommendation)

    assert has_element?(
             view,
             "#outreach-recommendation-notice[data-status='error']",
             "could not prepare a next step"
           )

    refute render(view) =~ "did not find enough evidence"
    assert has_element?(view, "#generate-outreach-recommendation")
  end

  test "keeps polling after a completed step queues the follow-up suggestion", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "outreach-completion-poll@tuist.dev"})
    contact = insert_contact!()

    {:ok, event, contact} =
      Outreach.record_event(contact, %{kind: "note", body: "Jordan asked for a follow up."})

    insert_pending_recommendation!(contact, event)

    {:ok, view, _html} = live(conn, ~p"/gtm/outreach/#{contact.id}")

    view
    |> element("#complete-outreach-recommendation")
    |> render_click()

    assert Outreach.recommendation_generation_pending?(contact)
    assert has_element?(view, "#outreach-recommendation-processing")
    refute has_element?(view, "#outreach-recommendation-empty")

    # Settle the job so the view stops polling before the test connection goes away.
    cancel_generation_job!(contact)
    send(view.pid, :poll_recommendation)
    refute has_element?(view, "#outreach-recommendation-processing")
  end

  test "leaves the contact page when the contact disappears mid-generation", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "outreach-deleted-contact@tuist.dev"})
    contact = insert_contact!()

    {:ok, view, _html} = live(conn, ~p"/gtm/outreach/#{contact.id}")

    view
    |> element("#generate-outreach-recommendation")
    |> render_click()

    cancel_generation_job!(contact)
    Repo.delete!(contact)
    send(view.pid, :poll_recommendation)

    assert_redirect(view, ~p"/gtm/outreach")
  end

  test "records connection progress and messages from the contact page", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "outreach-events@tuist.dev"})
    contact = insert_contact!()

    {:ok, view, _html} = live(conn, ~p"/gtm/outreach/#{contact.id}")

    render_click(view, "record_quick_event", %{"kind" => "connection_requested"})

    assert has_element?(view, "#outreach-contact-events", "Connection request sent")
    assert has_element?(view, "#generate-outreach-recommendation")

    render_click(view, "record_quick_event", %{"kind" => "connection_accepted"})

    view
    |> form("#outreach-event-form", %{
      "event" => %{
        "kind" => "message_sent",
        "body" => "I liked your point about build feedback. What made that difficult?"
      }
    })
    |> render_submit()

    assert has_element?(view, "#outreach-contact-events", "Message sent")
    assert has_element?(view, "#outreach-contact-events", "What made that difficult?")
    assert Repo.get!(Contact, contact.id).outreach_status == "conversation_started"
  end

  test "automatically records contact context from a pasted screenshot", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "outreach-screenshot@tuist.dev"})
    contact = insert_contact!()

    ScreenshotNoteAgent.put_response(
      contact.account_id,
      fn screenshots, %{id: account_id, name: account_name, contact_name: contact_name} ->
        assert account_id == contact.account_id
        assert account_name == "Acme Platforms"
        assert contact_name == "Jordan Lee"
        assert length(screenshots) == 1

        {:ok, "Jordan wants to compare the current workflow with Atlas before a follow-up."}
      end
    )

    {:ok, view, _html} = live(conn, ~p"/gtm/outreach/#{contact.id}")

    render_hook(view, "screenshots_pasted", %{
      "screenshots" => [
        %{
          "data" => Base.encode64(<<137, 80, 78, 71>>),
          "media_type" => "image/png",
          "size" => 4
        }
      ]
    })

    assert has_element?(view, "#outreach-screenshot-tray")
    assert has_element?(view, "#outreach-screenshot-processing", "Analyzing screenshot")
    refute has_element?(view, "#outreach-screenshot-retry")

    _html = render_async(view, 2_000)

    assert has_element?(view, "#outreach-contact-events", "Jordan wants to compare")
    refute has_element?(view, "#outreach-screenshot-tray")
    assert Repo.get!(Contact, contact.id).outreach_status == "not_contacted"
  end

  test "shows and completes the agent's guided next step", %{conn: conn} do
    {conn, user} = log_in_user(conn, %{email: "outreach-guidance@tuist.dev"})
    contact = insert_contact!()

    {:ok, evidence, contact} =
      Outreach.record_event(contact, %{
        kind: "message_received",
        body: "Helping teams trust the feedback is the hard part.",
        occurred_at: ~U[2026-07-20 10:00:00Z]
      })

    recommendation =
      %Recommendation{
        contact_id: contact.id,
        account_id: contact.account_id,
        source_event_id: evidence.id
      }
      |> Recommendation.changeset(%{
        status: "pending",
        action_type: "reply",
        recommended_event_kind: "message_sent",
        title: "Explore how Jordan builds trust",
        guidance: "Reflect the concern and ask one question.",
        rationale: "Jordan replied with a concrete organizational challenge.",
        draft_message: "How does your team decide which feedback engineers will trust?",
        due_at: ~U[2026-07-20 12:00:00Z],
        confidence: Decimal.new("0.91"),
        evidence: %{"items" => [%{"event_id" => evidence.id, "observation" => evidence.body}]},
        generated_by_agent: "outreach_recommendation_agent"
      })
      |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/gtm/outreach/#{contact.id}")

    assert has_element?(view, "#outreach-recommendation", recommendation.title)
    assert has_element?(view, "#outreach-recommendation", recommendation.draft_message)
    refute has_element?(view, "#outreach-recommendation-sent-subject")
    assert has_element?(view, "#complete-outreach-recommendation")

    sent_message = "How are you deciding which build feedback is trustworthy today?"

    view
    |> form("#outreach-recommendation-completion-form", %{
      "completion" => %{"sent_message" => sent_message}
    })
    |> render_submit()

    refute has_element?(view, "#outreach-recommendation")
    assert has_element?(view, "#outreach-contact-events", sent_message)
    assert Repo.get!(Recommendation, recommendation.id).reviewed_by_id == user.id

    attempt = Repo.get_by!(MessageAttempt, recommendation_id: recommendation.id)
    assert attempt.proposed_message == recommendation.draft_message
    assert attempt.sent_message == sent_message
  end

  test "shows and records the suggested connection request message in history", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "outreach-connection-note@tuist.dev"})
    contact = insert_contact!()

    {:ok, evidence, contact} =
      Outreach.record_event(contact, %{
        kind: "note",
        body: "Jordan leads developer productivity at Acme Platforms."
      })

    draft_message = "I appreciated your work on developer productivity and would like to connect."

    %Recommendation{
      contact_id: contact.id,
      account_id: contact.account_id,
      source_event_id: evidence.id
    }
    |> Recommendation.changeset(%{
      status: "pending",
      action_type: "connection_request",
      recommended_event_kind: "connection_requested",
      title: "Connect with Jordan",
      guidance: "Send a short, relevant connection request.",
      rationale: "Jordan's role is relevant to the observed developer productivity work.",
      draft_message: draft_message,
      due_at: ~U[2026-07-21 12:00:00Z],
      confidence: Decimal.new("0.88"),
      evidence: %{"items" => [%{"event_id" => evidence.id, "observation" => evidence.body}]},
      generated_by_agent: "outreach_recommendation_agent"
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/gtm/outreach/#{contact.id}")

    assert has_element?(
             view,
             "[data-part='next-step-card'] #outreach-recommendation",
             draft_message
           )

    assert has_element?(
             view,
             "#outreach-recommendation-completion-form",
             "Connection request message"
           )

    assert has_element?(view, "#outreach-recommendation-sent-message[maxlength='200']")
    refute has_element?(view, "#outreach-recommendation-sent-subject")

    sent_message = "I liked your perspective on developer productivity and would be glad to connect."

    view
    |> form("#outreach-recommendation-completion-form", %{
      "completion" => %{"sent_message" => sent_message}
    })
    |> render_submit()

    assert has_element?(view, "#outreach-contact-events", sent_message)
  end

  test "shows and records the visible InMail subject", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "outreach-inmail@tuist.dev"})
    contact = insert_contact!()

    {:ok, evidence, contact} =
      Outreach.record_event(contact, %{
        kind: "note",
        body: "Jordan described the challenge of making build feedback trustworthy."
      })

    recommendation =
      %Recommendation{
        contact_id: contact.id,
        account_id: contact.account_id,
        source_event_id: evidence.id
      }
      |> Recommendation.changeset(%{
        status: "pending",
        action_type: "inmail",
        recommended_event_kind: "message_sent",
        title: "Ask about trusted build feedback",
        guidance: "Send a concise InMail grounded in Jordan's work.",
        rationale: "Jordan's work provides a specific reason to reach out.",
        draft_subject: "Trust in build feedback",
        draft_message: "How does your team decide which build feedback engineers can trust?",
        due_at: ~U[2026-07-21 12:00:00Z],
        confidence: Decimal.new("0.88"),
        evidence: %{"items" => [%{"event_id" => evidence.id, "observation" => evidence.body}]},
        generated_by_agent: "outreach_recommendation_agent"
      })
      |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/gtm/outreach/#{contact.id}")

    assert has_element?(
             view,
             "#outreach-recommendation-sent-subject[value='Trust in build feedback']"
           )

    assert has_element?(view, "#outreach-recommendation-completion-form", "InMail message")
    assert has_element?(view, "#complete-outreach-recommendation", "Mark InMail sent")

    sent_subject = "Making build feedback trustworthy"
    sent_message = "How are you deciding which build feedback engineers can trust today?"

    view
    |> form("#outreach-recommendation-completion-form", %{
      "completion" => %{"sent_subject" => sent_subject, "sent_message" => sent_message}
    })
    |> render_submit()

    assert has_element?(view, "#outreach-contact-events", sent_subject)
    assert has_element?(view, "#outreach-contact-events", sent_message)

    attempt = Repo.get_by!(MessageAttempt, recommendation_id: recommendation.id)
    assert attempt.message_kind == "inmail"
    assert attempt.sent_subject == sent_subject
    assert attempt.sent_message == sent_message
  end

  test "opens every account contact history from the account page", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "outreach-account-link@tuist.dev"})
    contact = insert_contact!()

    {:ok, view, _html} = live(conn, ~p"/sales/accounts/#{contact.account_id}")

    assert has_element?(
             view,
             ~s(#contact-history-button-#{contact.id}[href="/gtm/outreach/#{contact.id}"])
           )
  end

  test "reviews Atlas-owned candidates before adding them to outreach", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "outreach-review@tuist.dev"})
    enroll_candidate = insert_candidate!("enroll")
    reject_candidate = insert_candidate!("reject")

    {:ok, view, _html} = live(conn, ~p"/gtm/outreach")

    assert has_element?(view, "#outreach-candidates-table")
    assert has_element?(view, "[data-part='outreach-candidates-card']", "Candidates")
    assert has_element?(view, "#outreach-candidate-actions-#{enroll_candidate.id}-button")
    assert has_element?(view, "#outreach-candidate-actions-#{reject_candidate.id}-content-portal")

    assert has_element?(
             view,
             ~s(#outreach-candidate-avatar-#{enroll_candidate.id} img[src="#{Avatar.gravatar_url(enroll_candidate.email)}"])
           )

    render_click(view, "reject_candidate", %{"id" => reject_candidate.id})

    refute has_element?(view, "#outreach-candidate-actions-#{reject_candidate.id}-button")
    assert Repo.get!(Candidate, reject_candidate.id).status == "rejected"

    view
    |> element("#outreach-candidate-actions-#{enroll_candidate.id}-button")
    |> render_click()

    refute has_element?(view, "#outreach-candidate-actions-#{enroll_candidate.id}-button")
    assert has_element?(view, "#outreach-contacts-table")
    assert Repo.get!(Candidate, enroll_candidate.id).status == "enrolled"
  end

  test "paginates outreach candidates", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "outreach-pagination@tuist.dev"})

    candidates =
      Enum.map(1..21, fn rank ->
        insert_candidate!("page-#{rank}", rank)
      end)

    last_candidate = List.last(candidates)

    {:ok, view, _html} = live(conn, ~p"/gtm/outreach")

    assert has_element?(view, "#outreach-candidates-pagination")
    assert has_element?(view, "#outreach-candidate-actions-#{List.first(candidates).id}-button")
    refute has_element?(view, "#outreach-candidate-actions-#{last_candidate.id}-button")

    view
    |> element(~s(#outreach-candidates-pagination a[data-part="page-button"][href*="candidates-page=2"]))
    |> render_click()

    assert_patched(view, ~p"/gtm/outreach?candidates-page=2")
    assert has_element?(view, "#outreach-candidate-actions-#{last_candidate.id}-button")
    refute has_element?(view, "#outreach-candidate-actions-#{List.first(candidates).id}-button")
  end

  defp insert_contact! do
    account =
      %Account{}
      |> Account.changeset(%{
        account_key: "outreach:#{System.unique_integer([:positive])}",
        name: "Acme Platforms",
        primary_domain: "acme.example",
        segment: :prospect
      })
      |> Repo.insert!()

    %Contact{account_id: account.id}
    |> Contact.outreach_changeset(%{
      full_name: "Jordan Lee",
      email: "jordan.lee@example.com",
      title: "Director of Developer Productivity",
      linkedin_url: "https://www.linkedin.com/in/jordan-lee",
      source: "apollo",
      source_id: "apollo-#{System.unique_integer([:positive])}",
      outreach_enrolled_at: ~U[2026-07-17 10:00:00Z]
    })
    |> Repo.insert!()
  end

  defp insert_candidate!(suffix, search_rank \\ 1) do
    %Candidate{}
    |> Candidate.changeset(%{
      source: "apollo",
      source_id: "candidate-#{suffix}-#{System.unique_integer([:positive])}",
      search_segment: "mobile_mid_large",
      search_version: 1,
      status: "pending",
      full_name: "Riley #{suffix}",
      email: "riley.#{suffix}@example.com",
      title: "Head of Mobile",
      organization_name: "Search #{suffix}",
      organization_source_id: "organization-#{suffix}",
      organization_domain: "search-#{suffix}.example",
      linkedin_url: "https://www.linkedin.com/in/riley-#{suffix}",
      search_rank: search_rank,
      discovered_at: ~U[2026-07-20 12:00:00Z]
    })
    |> Repo.insert!()
  end

  defp insert_pending_recommendation!(contact, event) do
    %Recommendation{contact_id: contact.id, account_id: contact.account_id, source_event_id: event.id}
    |> Recommendation.changeset(%{
      status: "pending",
      action_type: "wait",
      recommended_event_kind: "note",
      title: "Give Jordan room to reply",
      guidance: "Wait for a reply before sending anything else.",
      rationale: "Jordan asked for a follow up and has not answered yet.",
      due_at: ~U[2026-07-24 12:00:00Z],
      confidence: Decimal.new("0.81"),
      evidence: %{"items" => [%{"event_id" => event.id, "observation" => event.body}]},
      generated_by_agent: "outreach_recommendation_agent"
    })
    |> Repo.insert!()
  end

  defp cancel_generation_job!(contact) do
    Oban.Job
    |> where([job], fragment("?->>'contact_id' = ?", job.args, ^contact.id))
    |> Repo.update_all(set: [state: "cancelled"])
  end
end
