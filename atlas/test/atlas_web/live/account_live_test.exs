defmodule AtlasWeb.AccountLiveTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountAttentionSuggestion
  alias Atlas.Accounts.AccountHandle
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.Invoice
  alias Atlas.Accounts.Outcome
  alias Atlas.Accounts.OutcomeProposal
  alias Atlas.Accounts.ServiceLevel
  alias Atlas.Accounts.ServiceLevelExtractionCheck
  alias Atlas.Authorization.Roles
  alias Atlas.Authorization.UserRole
  alias Atlas.Documents.Document
  alias Atlas.Letters
  alias Atlas.Repo
  alias Atlas.Slack
  alias Atlas.Slack.Message, as: SlackMessage
  alias Atlas.TestSupport.ScreenshotNoteAgent
  alias Atlas.Users.User

  setup :verify_on_exit!

  test "shows the tax certificate request action only to leadership", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    executive = insert_user!("letter-executive-#{suffix}@tuist.dev", %{role: :executive})
    account = insert_tax_certificate_account!(suffix)
    conn = init_test_session(conn, %{"user_id" => executive.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    assert has_element?(view, "#tax-certificate-request-modal [data-part='trigger']")
    refute has_element?(view, "[data-part='government-letters-card']")
  end

  test "does not expose postal letter controls to employees", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    employee = insert_user!("letter-employee-#{suffix}@tuist.dev")
    account = insert_tax_certificate_account!(suffix)
    conn = init_test_session(conn, %{"user_id" => employee.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    refute has_element?(view, "[data-part='government-letters-card']")
    refute has_element?(view, "#tax-certificate-request-modal")
  end

  test "lets leadership download ready-to-sign tax certificate requests from the account", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    executive = insert_user!("account-letter-executive-#{suffix}@tuist.dev", %{role: :executive})
    account = insert_tax_certificate_account!(suffix)

    assert {:ok, letter} =
             Letters.prepare_tax_certificate(account, tax_certificate_attrs(), executive)

    conn = init_test_session(conn, %{"user_id" => executive.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    assert has_element?(view, "[data-part='ready-to-sign-tax-certificate-requests-card']")

    assert has_element?(
             view,
             "#download-ready-to-sign-tax-certificate-request-#{letter.id}"
           )

    assert has_element?(view, "#upload-signed-tax-certificate-request-#{letter.id}")
  end

  test "renders contacts, upcoming invoices, and the account timeline", %{conn: conn} do
    user = insert_user!("owner@example.com")

    account =
      insert_account!(%{
        account_key: "enterprise:delivery_hero",
        name: "Acme",
        segment: :customer,
        currency: "eur",
        current_value: 7_980,
        primary_domain: "deliveryhero.com"
      })

    contact =
      insert_contact!(account, %{
        full_name: "Begum Dagistan",
        email: "begum@deliveryhero.com",
        source: "operate"
      })

    account_handle =
      insert_account_handle!(account, %{
        handle: "deliveryhero-production",
        source: "enterprise"
      })

    upcoming_invoice =
      insert_invoice!(account, %{
        external_id: "enterprise-invoice:delivery_hero:1",
        source: "enterprise",
        due_date: Date.add(Date.utc_today(), 14),
        amount_value: Decimal.new("4200"),
        amount_currency: "eur",
        status: "scheduled"
      })

    insert_invoice!(account, %{
      external_id: "enterprise-invoice:delivery_hero:past",
      source: "enterprise",
      due_date: Date.add(Date.utc_today(), -30),
      amount_value: Decimal.new("100"),
      amount_currency: "eur",
      status: "paid"
    })

    event =
      insert_event!(account, %{
        external_id: "operate-note:note-1",
        source: "operate",
        kind: "note",
        title: "Follow-up shared",
        occurred_at: ~U[2026-05-10 00:00:00Z]
      })

    document = insert_document!(account, %{title: "Acme MSA"})

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    assert has_element?(view, "#account")
    assert has_element?(view, "[data-part='overview-card']", "Handles")
    assert has_element?(view, "#account-website-link[href='https://#{account.primary_domain}']")
    assert has_element?(view, "#edit-account-button")
    assert has_element?(view, "#add-contact-button")
    refute has_element?(view, "[data-part='outcomes-card']")
    assert has_element?(view, "#account-handle-#{account_handle.id}", account_handle.handle)
    assert has_element?(view, "#contact-#{contact.id} [data-part='contact-name']", contact.full_name)
    assert has_element?(view, "#contact-#{contact.id} [data-part='contact-email']", contact.email)
    assert has_element?(view, "#contact-#{contact.id} [data-part='contact-notes']", "No notes yet")
    assert has_element?(view, "#account-invoices-table", "EUR 4,200.00")
    assert has_element?(view, "#account-invoices-table", "scheduled")
    assert has_element?(view, "#account-document-#{document.id}", document.title)
    refute render(view) =~ "EUR 100.00"
    assert has_element?(view, "[data-part='metadata-value']", "Customer")
    assert has_element?(view, "[data-part='metadata-title']", "Lifecycle")
    assert has_element?(view, "[data-part='metadata-title']", "Handles")
    assert has_element?(view, "[data-part='metadata-value']", "EUR 7,980.00")
    assert has_element?(view, "#timeline-event-#{event.id}", event.title)
    _ = upcoming_invoice
  end

  test "renders the account attention queue", %{conn: conn} do
    user = insert_user!("account-attention@example.com")
    account = insert_account!(%{name: "Attention Customer", segment: :customer})

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    assert has_element?(view, "[data-part='account-attention-card']")
    assert has_element?(view, "#generate-attention-suggestions-button")
    assert has_element?(view, "#account-attention-empty")
  end

  test "acts on an account attention suggestion", %{conn: conn} do
    user = insert_user!("account-attention-actions@example.com")
    account = insert_account!(%{name: "Attention Customer", segment: :customer})
    suggestion = insert_account_attention_suggestion!(account)

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    assert has_element?(view, "#account-attention-suggestion-actions-#{suggestion.id}")
    assert has_element?(view, "#account-attention-suggestion-actions-#{suggestion.id}-button")

    view
    |> element("#account-attention-suggestion-actions-#{suggestion.id}-button")
    |> render_click()

    refute has_element?(view, "#account-attention-suggestion-#{suggestion.id}")
    assert Repo.get!(AccountAttentionSuggestion, suggestion.id).status == "actioned"
  end

  test "renders extracted service levels from signed documents", %{conn: conn} do
    user = insert_user!("service-level@example.com")
    account = insert_account!(%{name: "Service Level Customer", segment: :customer})
    document = insert_document!(account, %{title: "Service Level Customer SLA"})
    check = insert_service_level_extraction_check!(account, document)

    service_level =
      insert_service_level!(account, document, check, %{
        name: "Monthly uptime",
        category: "availability",
        target: "99.9% monthly uptime",
        measurement_window: "monthly",
        applies_from: ~D[2026-01-01],
        applies_until: ~D[2026-12-31],
        service_credit: "Credits apply below the uptime target.",
        exclusions: "Scheduled maintenance is excluded.",
        source_page: 3,
        source_excerpt: "Monthly uptime will be at least 99.9%."
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    assert has_element?(view, "#account-service-level-#{service_level.id}", "Monthly uptime")
    assert has_element?(view, "#account-service-level-#{service_level.id}", "99.9% monthly uptime")
    assert has_element?(view, "#account-service-level-#{service_level.id}", "Credits apply")
    assert has_element?(view, "#service-level-document-#{service_level.id}", "Service Level Customer SLA")
  end

  test "renders Granola meeting event bodies as markdown", %{conn: conn} do
    user = insert_user!("meeting-markdown@example.com")
    account = insert_account!(%{name: "Acme", segment: :customer})

    event =
      insert_event!(account, %{
        external_id: "not_renewal",
        source: "granola",
        kind: "meeting",
        title: "Renewal planning",
        body: "## Next Steps\n\n- Send renewal proposal.",
        occurred_at: ~U[2026-05-07 13:30:00Z]
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    assert has_element?(
             view,
             "#timeline-event-#{event.id} [data-part='timeline-event-body'] h2",
             "Next Steps"
           )

    assert has_element?(
             view,
             "#timeline-event-#{event.id} [data-part='timeline-event-body'] li",
             "Send renewal proposal."
           )
  end

  test "hides documents section when the account has no documents", %{conn: conn} do
    user = insert_user!("no-documents@example.com")
    account = insert_account!(%{name: "No Documents Account", segment: :customer})

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    refute has_element?(view, "[data-part='documents-card']")
    refute has_element?(view, "#account-documents-list")
  end

  test "adds a note to the timeline through the composer", %{conn: conn} do
    user = insert_user!("notes-timeline@example.com")

    account =
      insert_account!(%{
        account_key: "enterprise:northstar",
        name: "Northstar",
        segment: :customer
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    render_submit(view, "add_note", %{
      "note" => %{"body" => "Pricing call lined up with the procurement team."}
    })

    event =
      Repo.get_by!(Event,
        account_id: account.id,
        source: "atlas",
        kind: "note"
      )

    assert event.body == "Pricing call lined up with the procurement team."
    assert event.author_id == user.id

    assert has_element?(
             view,
             "#timeline-event-#{event.id} [data-part='timeline-event-title']",
             "Note"
           )

    assert has_element?(
             view,
             "#timeline-event-#{event.id} [data-part='timeline-event-author']",
             "Atlas User"
           )

    assert has_element?(
             view,
             "#timeline-event-#{event.id} [data-part='timeline-event-body']",
             "Pricing call lined up"
           )
  end

  @tag :skip
  test "creates, reviews, and achieves a customer outcome from the account page", %{conn: conn} do
    user = insert_user!("outcomes@example.com")

    account =
      insert_account!(%{
        account_key: "enterprise:outcomes",
        name: "Outcome Customer",
        segment: :customer
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    render_submit(view, "save_outcome", %{
      "outcome" => %{
        "title" => "Reach weekly adoption target",
        "motion" => "adoption",
        "success_measure" => "Weekly active developers",
        "baseline" => "12",
        "target" => "30",
        "target_date" => "2026-08-31",
        "description" => "Expand repeat use across the mobile organization."
      }
    })

    outcome = Repo.get_by!(Outcome, account_id: account.id, title: "Reach weekly adoption target")

    assert outcome.owner_id == user.id
    assert outcome.status == "active"
    assert outcome.health == "unknown"
    assert outcome.target_date == ~D[2026-08-31]

    assert has_element?(
             view,
             "#outcome-#{outcome.id} [data-part='outcome-title']",
             "Reach weekly adoption target"
           )

    assert has_element?(view, "#outcome-#{outcome.id}", "12")
    assert has_element?(view, "#outcome-#{outcome.id}", "30")

    view
    |> element("#review-outcome-button-#{outcome.id}")
    |> render_click()

    render_submit(view, "save_outcome_review", %{
      "outcome_review" => %{
        "health" => "at_risk",
        "summary" => "Usage increased, but the second team rollout slipped.",
        "recommendation" => "Pair with the delayed team on its first successful rollout."
      }
    })

    reviewed = Accounts.get_outcome(outcome.id)
    assert reviewed.health == "at_risk"
    assert length(reviewed.reviews) == 1
    assert has_element?(view, "#outcome-health-#{outcome.id}", "At risk")
    assert has_element?(view, "#outcome-#{outcome.id}", "Usage increased")

    view
    |> element("#achieve-outcome-button-#{outcome.id}")
    |> render_click()

    achieved = Repo.get!(Outcome, outcome.id)
    assert achieved.status == "achieved"
    assert achieved.health == "on_track"
    assert achieved.achieved_at
    assert has_element?(view, "#outcome-status-#{outcome.id}", "Achieved")
  end

  @tag :skip
  test "reviews agent outcome suggestions before applying them", %{conn: conn} do
    user = insert_user!("outcome-proposals@example.com")
    account = insert_account!(%{name: "Proposal Customer", segment: :customer})

    event =
      insert_event!(account, %{
        external_id: "granola:proposal-evidence",
        source: "granola",
        kind: "meeting",
        title: "Adoption planning",
        body: "The customer wants 40 weekly active developers before renewal.",
        occurred_at: ~U[2026-07-15 10:00:00Z]
      })

    {:ok, existing_outcome} =
      Accounts.create_outcome(
        account,
        %{
          title: "Complete the evaluation",
          motion: "evaluation",
          success_measure: "Successful production build"
        },
        user
      )

    evidence = %{
      "items" => [
        %{
          "event_id" => event.id,
          "observation" => "The customer named 40 weekly active developers as its renewal target."
        }
      ]
    }

    {:ok, new_outcome_proposal} =
      Accounts.create_outcome_proposal(account, %{
        proposal_type: "new_outcome",
        title: "Reach weekly team adoption",
        description: "Make adoption repeatable before the renewal decision.",
        motion: "adoption",
        success_measure: "Weekly active developers",
        baseline: "18 developers",
        target: "40 developers",
        target_date: ~D[2026-09-30],
        evidence: evidence,
        confidence: Decimal.new("0.91"),
        rationale: "The customer supplied a measurable result and deadline.",
        generated_by_agent: "outcome_proposal_agent"
      })

    {:ok, review_proposal} =
      Accounts.create_outcome_proposal(account, %{
        proposal_type: "outcome_review",
        outcome_id: existing_outcome.id,
        health: "at_risk",
        summary: "The production build is not yet complete.",
        recommendation: "Schedule a focused build session with the platform team.",
        evidence: evidence,
        confidence: Decimal.new("0.84"),
        rationale: "The latest meeting introduced material delivery risk.",
        generated_by_agent: "outcome_proposal_agent"
      })

    conn = init_test_session(conn, %{"user_id" => user.id})
    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    assert has_element?(view, "#suggest-outcomes-button")
    assert has_element?(view, "#account-outcome-proposals")
    assert has_element?(view, "#outcome-proposal-#{new_outcome_proposal.id}", "Reach weekly team adoption")
    assert has_element?(view, "#outcome-proposal-#{review_proposal.id}", "Review Complete the evaluation")

    click_html =
      view
      |> element("#review-outcome-proposal-button-#{new_outcome_proposal.id}")
      |> render_click()

    proposal_modal = LazyHTML.from_fragment(click_html)
    assert LazyHTML.text(proposal_modal) =~ "The customer named 40 weekly active developers"

    render_submit(view, "approve_outcome_proposal", %{
      "outcome_proposal" => %{
        "title" => "Reach weekly product adoption",
        "description" => "Make adoption repeatable before the renewal decision.",
        "motion" => "adoption",
        "success_measure" => "Weekly active developers",
        "baseline" => "18 developers",
        "target" => "40 developers",
        "target_date" => "2026-09-30"
      }
    })

    approved = Repo.get!(OutcomeProposal, new_outcome_proposal.id)
    created_outcome = Repo.get_by!(Outcome, account_id: account.id, title: "Reach weekly product adoption")
    assert approved.status == "approved"
    assert approved.outcome_id == created_outcome.id
    assert created_outcome.owner_id == user.id
    refute has_element?(view, "#outcome-proposal-#{new_outcome_proposal.id}")

    view
    |> element("#review-outcome-proposal-button-#{review_proposal.id}")
    |> render_click()

    render_submit(view, "reject_outcome_proposal", %{
      "proposal_decision" => %{"reason" => "The build date moved after this meeting."}
    })

    rejected = Repo.get!(OutcomeProposal, review_proposal.id)
    assert rejected.status == "rejected"
    assert rejected.rejection_reason == "The build date moved after this meeting."
    refute has_element?(view, "#account-outcome-proposals")
  end

  test "sanitizes XSS payloads from timeline event bodies", %{conn: conn} do
    user = insert_user!("xss-timeline@example.com")

    account =
      insert_account!(%{
        account_key: "enterprise:safehaven",
        name: "Safehaven",
        segment: :customer
      })

    event =
      insert_event!(account, %{
        external_id: "operate-note:xss-1",
        source: "operate",
        kind: "note",
        title: "Suspicious note",
        body: "<script>alert('xss')</script>\n\n[click me](javascript:alert('xss'))",
        occurred_at: ~U[2026-05-10 00:00:00Z]
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    rendered = render(view)
    body_selector = "#timeline-event-#{event.id} [data-part='timeline-event-body']"

    assert has_element?(view, body_selector)
    refute rendered =~ "<script>"
    refute rendered =~ "javascript:"
  end

  describe "screenshot paste" do
    test "rejects screenshots above the size limit", %{conn: conn} do
      user = insert_user!("paste-too-big@example.com")

      account =
        insert_account!(%{
          account_key: "enterprise:bigfile",
          name: "Bigfile",
          segment: :customer
        })

      conn = init_test_session(conn, %{"user_id" => user.id})

      {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

      render_hook(view, "screenshot_pasted", %{
        "data" => Base.encode64(<<0, 0, 0>>),
        "media_type" => "image/png",
        "size" => 6 * 1024 * 1024
      })

      assert has_element?(view, "#timeline-note-error", "Screenshot is too large")
      refute has_element?(view, "[data-part='timeline-note-processing']")
    end

    test "rejects unsupported screenshot media types", %{conn: conn} do
      user = insert_user!("paste-bad-mime@example.com")

      account =
        insert_account!(%{
          account_key: "enterprise:badmime",
          name: "Badmime",
          segment: :customer
        })

      conn = init_test_session(conn, %{"user_id" => user.id})

      {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

      render_hook(view, "screenshot_pasted", %{
        "data" => Base.encode64(<<0, 0, 0>>),
        "media_type" => "application/pdf",
        "size" => 1024
      })

      assert has_element?(view, "#timeline-note-error", "Unsupported screenshot format")
    end

    test "automatically records an account note from pasted screenshots", %{
      conn: conn
    } do
      user = insert_user!("paste-success@example.com")

      account =
        insert_account!(%{
          account_key: "enterprise:goodpaste",
          name: "Goodpaste",
          segment: :customer
        })

      ScreenshotNoteAgent.put_response(account.id, fn screenshots, %{id: account_id, name: "Goodpaste"} ->
        assert account_id == account.id
        assert length(screenshots) == 2

        {:ok, "Drafted sales note from screenshot."}
      end)

      conn = init_test_session(conn, %{"user_id" => user.id})
      {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

      first_screenshot = Base.encode64(<<137, 80, 78, 71>>)

      render_hook(view, "screenshots_pasted", %{
        "screenshots" => [
          %{
            "data" => first_screenshot,
            "media_type" => "image/png",
            "size" => 4
          },
          %{
            "data" => Base.encode64(<<255, 216, 255>>),
            "media_type" => "image/jpeg",
            "size" => 3
          }
        ]
      })

      assert has_element?(view, "#timeline-screenshot-tray")
      assert has_element?(view, "#timeline-note-processing", "Analyzing 2 screenshots")
      refute has_element?(view, "#timeline-screenshot-retry")

      html = render_async(view, 2_000)

      refute html =~ "Analyzing 2 screenshots"

      event =
        Repo.get_by!(Event,
          account_id: account.id,
          source: "atlas",
          kind: "note"
        )

      assert event.body == "Drafted sales note from screenshot."
      assert event.author_id == user.id
      assert has_element?(view, "#timeline-event-#{event.id}", "Drafted sales note from screenshot.")
      refute has_element?(view, "#timeline-screenshot-tray")
    end

    test "surfaces an error when the language model is not configured", %{conn: conn} do
      user = insert_user!("paste-no-provider@example.com")

      account =
        insert_account!(%{
          account_key: "enterprise:noprovider",
          name: "Noprovider",
          segment: :customer
        })

      ScreenshotNoteAgent.put_response(account.id, fn _screenshots, _ctx ->
        {:error, :llm_not_configured}
      end)

      conn = init_test_session(conn, %{"user_id" => user.id})
      {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

      render_hook(view, "screenshot_pasted", %{
        "data" => Base.encode64(<<137, 80, 78, 71>>),
        "media_type" => "image/png",
        "size" => 4
      })

      _ = render_async(view, 2_000)

      assert has_element?(view, "#timeline-note-error", "Language model is not configured")
      assert has_element?(view, "#timeline-screenshot-retry", "Try screenshot again")
    end

    test "removes and clears staged screenshots", %{conn: conn} do
      user = insert_user!("paste-remove@example.com")

      account =
        insert_account!(%{
          account_key: "enterprise:remove",
          name: "Remove",
          segment: :customer
        })

      conn = init_test_session(conn, %{"user_id" => user.id})
      {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

      first_screenshot = Base.encode64(<<137, 80, 78, 71>>)

      ScreenshotNoteAgent.put_response(account.id, {:error, :llm_not_configured})

      render_hook(view, "screenshots_pasted", %{
        "screenshots" => [
          %{
            "data" => first_screenshot,
            "media_type" => "image/png",
            "size" => 4
          },
          %{
            "data" => Base.encode64(<<255, 216, 255>>),
            "media_type" => "image/jpeg",
            "size" => 3
          }
        ]
      })

      _ = render_async(view, 2_000)

      assert has_element?(view, "[data-part='timeline-screenshot-count']", "2 screenshots ready")
      assert has_element?(view, "#timeline-screenshot-retry")

      view
      |> element("#remove-#{staged_screenshot_id(first_screenshot)}")
      |> render_click()

      assert has_element?(view, "[data-part='timeline-screenshot-count']", "1 screenshot ready")

      view
      |> element("#timeline-screenshot-clear")
      |> render_click()

      refute has_element?(view, "#timeline-screenshot-tray")
    end
  end

  test "renders Slack-linked channels and the Slack-themed timeline event with thread replies",
       %{conn: conn} do
    user = insert_user!("slack-timeline@example.com")

    account =
      insert_account!(%{
        account_key: "enterprise:slack-fixture",
        name: "Slack Fixture",
        segment: :customer
      })

    {:ok, channel} =
      Slack.add_channel(%{
        channel_id: "C_FIXTURE",
        channel_name: "fixture-channel",
        account_id: account.id
      })

    {:ok, internal_user} =
      Slack.upsert_user(:company, %{
        slack_user_id: "U_INT",
        name: "internal",
        display_name: "internal",
        avatar_url: "https://avatars.example.com/internal.png",
        is_external: false
      })

    {:ok, external_user} =
      Slack.upsert_user(:company, %{
        slack_user_id: "U_EXT",
        name: "customer",
        display_name: "customer.user",
        avatar_url: "https://avatars.example.com/customer.png",
        is_external: true
      })

    permalink = "https://acme.slack.com/archives/C_FIXTURE/p1714000000100100"

    parent_event =
      %Event{}
      |> Event.changeset(%{
        external_id: "slack:company:C_FIXTURE:1714000000.100100",
        source: "slack",
        kind: "slack_message",
        title: "Customer asked about onboarding",
        body: "Hey <@U_INT>, could you share the onboarding doc?",
        occurred_at: ~U[2026-04-26 09:00:00Z],
        url: permalink,
        account_id: account.id,
        metadata: %{
          "slack_app" => "company",
          "channel_id" => "C_FIXTURE",
          "channel_name" => "fixture-channel",
          "slack_ts" => "1714000000.100100",
          "author_slack_user_id" => external_user.slack_user_id,
          "author_name" => "customer.user",
          "author_avatar_url" => "https://avatars.example.com/customer.png",
          "author_is_external" => true,
          "author_is_bot" => false
        }
      })
      |> Repo.insert!()

    {:ok, _parent_message} =
      Slack.insert_message(channel, external_user, parent_event, %{
        slack_ts: "1714000000.100100",
        thread_ts: nil,
        text: "Hey <@U_INT>, could you share the onboarding doc?",
        permalink: permalink,
        posted_at: ~U[2026-04-26 09:00:00Z]
      })

    {:ok, reply} =
      Slack.insert_message(channel, internal_user, nil, %{
        slack_ts: "1714000300.200200",
        thread_ts: "1714000000.100100",
        text:
          "&gt; Could you share the onboarding doc?\nReplying with <https://docs.example.com/onboarding|the onboarding doc> &amp; next steps.",
        permalink: "https://acme.slack.com/archives/C_FIXTURE/p1714000300200200",
        posted_at: ~U[2026-04-26 09:05:00Z]
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    assert has_element?(view, "#account-slack-channel-link", "Company / #fixture-channel")
    _ = channel

    assert has_element?(
             view,
             "#timeline-event-#{parent_event.id}[data-variant='slack']"
           )

    assert has_element?(
             view,
             "#timeline-event-#{parent_event.id} [data-part='slack-message-author-name']",
             "customer.user"
           )

    assert has_element?(
             view,
             "#timeline-event-#{parent_event.id} [data-part='slack-message-customer-tag']",
             "Customer"
           )

    assert has_element?(
             view,
             "#timeline-event-#{parent_event.id} [data-part='slack-channel-tag']",
             "Company / #fixture-channel"
           )

    assert has_element?(
             view,
             "#timeline-event-#{parent_event.id} [data-part='slack-message-link'][href='#{permalink}']"
           )

    assert has_element?(
             view,
             "#timeline-event-#{parent_event.id} [data-part='slack-message-body']",
             "Hey @internal, could you share the onboarding doc?"
           )

    assert has_element?(
             view,
             "#slack-thread-reply-#{reply.id} [data-part='slack-thread-reply-author']",
             "internal"
           )

    assert has_element?(
             view,
             "#slack-thread-reply-#{reply.id} [data-part='slack-thread-reply-body'] blockquote",
             "Could you share the onboarding doc?"
           )

    assert has_element?(
             view,
             "#slack-thread-reply-#{reply.id} [data-part='slack-thread-reply-body'] a[href='https://docs.example.com/onboarding']",
             "the onboarding doc"
           )

    refute has_element?(
             view,
             "#slack-thread-reply-#{reply.id} [data-part='slack-message-customer-tag']"
           )

    # Make sure the parent slack_message row was actually persisted with the
    # expected schema-level relationship (regression guard for changeset drift).
    parent_message =
      from(m in SlackMessage, where: m.account_event_id == ^parent_event.id) |> Repo.one!()

    assert parent_message.slack_user_id == external_user.id
  end

  test "hides the upcoming invoices card when no future invoices exist", %{conn: conn} do
    user = insert_user!("noinvoices@example.com")

    account =
      insert_account!(%{
        account_key: "enterprise:cleartile",
        name: "Cleartile",
        segment: :customer
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    refute has_element?(view, "[data-part='invoices-card']")
  end

  test "renders reconciled Stripe invoices for accounts with a customer ID", %{conn: conn} do
    user = insert_user!("stripe-invoices@example.com")

    account =
      insert_account!(%{
        account_key: "enterprise:stripe_customer",
        name: "Stripe Customer",
        segment: :customer,
        stripe_customer_id: "cus_123"
      })

    insert_invoice!(account, %{
      external_id: "in_123",
      source: "stripe",
      number: "TUIST-8002",
      due_date: Date.add(Date.utc_today(), -30),
      amount_value: Decimal.new("30000.00"),
      amount_currency: "usd",
      status: "paid",
      stripe_url: "https://stripe.example/invoices/in_123"
    })

    insert_invoice!(account, %{
      external_id: "in_zero",
      source: "stripe",
      number: "TUIST-0000",
      due_date: Date.utc_today(),
      amount_value: Decimal.new("0.00"),
      amount_currency: "usd",
      status: "paid",
      stripe_url: "https://stripe.example/invoices/in_zero"
    })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    refute has_element?(view, "[data-part='invoices-source-label']")
    assert has_element?(view, "#account-invoices-table", "TUIST-8002")
    assert has_element?(view, "#account-invoices-table", "USD 30,000.00")
    assert has_element?(view, "#account-invoices-table a[href='https://stripe.example/invoices/in_123']")
    refute has_element?(view, "#account-invoices-table", "TUIST-0000")
  end

  test "paginates reconciled Stripe invoices on the account detail page", %{conn: conn} do
    user = insert_user!("stripe-invoices-pagination@example.com")

    account =
      insert_account!(%{
        account_key: "enterprise:stripe_customer_paginated",
        name: "Stripe Customer Paginated",
        segment: :customer,
        stripe_customer_id: "cus_paginated"
      })

    for index <- 1..6 do
      insert_invoice!(account, %{
        external_id: "in_page_#{index}",
        source: "stripe",
        number: "TUIST-PAGE-#{index}",
        due_date: ~D[2026-01-01] |> Date.add(index),
        amount_value: Decimal.new("100.00"),
        amount_currency: "usd",
        status: "paid",
        stripe_url: "https://stripe.example/invoices/in_page_#{index}"
      })
    end

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    assert has_element?(view, "#account-invoices-table", "TUIST-PAGE-6")
    refute has_element?(view, "#account-invoices-table", "TUIST-PAGE-1")
    assert has_element?(view, "a[href*='invoices-page=2']")

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}?invoices-page=2")

    assert has_element?(view, "#account-invoices-table", "TUIST-PAGE-1")
    refute has_element?(view, "#account-invoices-table", "TUIST-PAGE-6")
  end

  test "adds and removes handles through the management workflow", %{conn: conn} do
    user = insert_user!("handles@example.com")

    account =
      insert_account!(%{
        account_key: "enterprise:bluebird",
        name: "Bluebird Health",
        segment: :prospect
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    assert has_element?(view, "[data-part='overview-card']", "Handles")
    assert has_element?(view, "#edit-account-button")

    render_hook(view, "add_handle", %{"account_handle" => %{"handle" => "bluebird-production"}})

    account_handle =
      Repo.get_by!(AccountHandle, account_id: account.id, handle: "bluebird-production")

    assert account_handle.source == "atlas"
    assert has_element?(view, "#account-handle-#{account_handle.id}", "bluebird-production")

    render_hook(view, "remove_handle", %{"data" => account_handle.id})

    refute Repo.get(AccountHandle, account_handle.id)
    refute has_element?(view, "#account-handle-#{account_handle.id}")
  end

  test "adds a local contact with notes from the account page", %{conn: conn} do
    user = insert_user!("contacts@example.com")

    account =
      insert_account!(%{
        account_key: "enterprise:riverside",
        name: "Riverside",
        segment: :customer,
        contacts_count: 0
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    render_submit(view, "save_contact", %{
      "contact" => %{
        "full_name" => "Nora Jensen",
        "email" => "nora@riverside.fm",
        "title" => "Platform lead",
        "notes" => "Prefers async follow-ups and shares detailed product feedback."
      }
    })

    contact = Repo.get_by!(Contact, account_id: account.id, email: "nora@riverside.fm")
    account = Repo.get!(Account, account.id)

    assert contact.title == "Platform lead"
    assert contact.notes == "Prefers async follow-ups and shares detailed product feedback."
    assert account.contacts_count == 1
    assert has_element?(view, "#contact-#{contact.id} [data-part='contact-name']", "Nora Jensen")

    assert has_element?(
             view,
             "#contact-#{contact.id} [data-part='contact-notes']",
             "Prefers async follow-ups"
           )
  end

  test "stores notes on existing contacts", %{conn: conn} do
    user = insert_user!("notes@example.com")

    account =
      insert_account!(%{
        account_key: "operate:delivery_hero",
        name: "Acme",
        segment: :customer
      })

    contact =
      insert_contact!(account, %{
        full_name: "Begum Dagistan",
        email: "begum@deliveryhero.com",
        source: "enterprise"
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    view
    |> element("#edit-contact-button-#{contact.id}")
    |> render_click()

    render_submit(view, "save_contact", %{
      "contact" => %{
        "notes" => "Values tight agendas and responds best to concrete next steps."
      }
    })

    updated_contact = Repo.get!(Contact, contact.id)

    assert updated_contact.notes == "Values tight agendas and responds best to concrete next steps."

    assert has_element?(
             view,
             "#contact-#{contact.id} [data-part='contact-notes']",
             "Values tight agendas"
           )
  end

  test "updates account configuration through the edit workflow", %{conn: conn} do
    user = insert_user!("editing@example.com")
    parent = insert_account!(%{account_key: "operate:parent", name: "Acme Holding"})

    account =
      insert_account!(%{
        account_key: "operate:delivery_hero",
        name: "Acme",
        segment: :prospect,
        currency: "eur",
        current_value: 67_200,
        primary_domain: "deliveryhero.com"
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    render_submit(view, "save_account", %{
      "account" => %{
        "name" => "Acme Group",
        "description" => "Strategic enterprise customer",
        "primary_domain" => "deliveryhero.example",
        "parent_account_id" => parent.id,
        "segment" => "customer",
        "hosting" => "self_hosted",
        "currency" => "usd",
        "current_value" => "72000.50",
        "next_renewal_date" => "2027-03-15",
        "stripe_customer_id" => "cus_123"
      }
    })

    updated_account = Repo.get!(Account, account.id)

    assert updated_account.name == "Acme Group"
    assert updated_account.description == "Strategic enterprise customer"
    assert updated_account.primary_domain == "deliveryhero.example"
    assert updated_account.parent_account_id == parent.id
    assert updated_account.segment == :customer
    assert updated_account.hosting == "self_hosted"
    assert updated_account.currency == "USD"
    assert Decimal.equal?(updated_account.current_value, Decimal.new("72000.50"))
    assert updated_account.next_renewal_date == ~D[2027-03-15]
    assert updated_account.stripe_customer_id == "cus_123"

    assert has_element?(view, "#account [data-part='label']", "Acme Group")
    assert has_element?(view, "#account-parent-link[href='/commercial/sales/accounts/#{parent.id}']", "Acme Holding")
    assert has_element?(view, "[data-part='metadata-value']", "deliveryhero.example")
    assert has_element?(view, "[data-part='metadata-value']", "Customer")
    assert has_element?(view, "#account-stripe-link[href='https://dashboard.stripe.com/customers/cus_123']")
  end

  test "clears a parent account through the edit workflow", %{conn: conn} do
    user = insert_user!("clear-parent@example.com")
    parent = insert_account!(%{account_key: "operate:parent-clear", name: "Parent Company"})

    account =
      insert_account!(%{
        account_key: "operate:child_clear_parent",
        name: "Child Company",
        segment: :customer,
        parent_account_id: parent.id
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    render_submit(view, "save_account", %{
      "account" => %{
        "name" => "Child Company",
        "segment" => "customer",
        "parent_account_id" => "_none"
      }
    })

    assert Repo.get!(Account, account.id).parent_account_id == nil
    refute has_element?(view, "#account-parent-link")
  end

  test "uses a non-empty Slack none option and unlinks it on save", %{conn: conn} do
    user = insert_user!("slack-none@example.com")
    account = insert_account!(%{name: "Slack None", segment: :customer})

    {:ok, channel} =
      Slack.add_channel(%{
        account_id: account.id,
        channel_id: "C_NONE_TEST",
        channel_name: "support"
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    render_submit(view, "save_account", %{
      "account" => %{
        "name" => account.name,
        "segment" => "customer",
        "slack_channel" => "_none"
      }
    })

    assert Repo.reload(channel).account_id == nil
  end

  test "links a Slack channel through the account save workflow", %{conn: conn} do
    user = insert_user!("slack-picker@example.com")
    account = insert_account!(%{name: "Slack Picker", segment: :customer})

    {:ok, channel} =
      Slack.add_channel(%{
        channel_id: "C_PICKER",
        channel_name: "customer-success"
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    render_submit(view, "save_account", %{
      "account" => %{
        "name" => account.name,
        "segment" => "customer",
        "slack_channel" => "company:C_PICKER"
      }
    })

    assert Repo.reload(channel).account_id == account.id
    assert has_element?(view, "#account-slack-channel-link", "Company / #customer-success")
  end

  test "deletes an account and redirects to the accounts list", %{conn: conn} do
    user = insert_user!("deleter@example.com")

    account =
      insert_account!(%{
        account_key: "operate:to_delete",
        name: "To Delete",
        segment: :prospect
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    assert has_element?(view, "#account-actions-dropdown")

    assert {:error, {:live_redirect, %{to: "/commercial/sales/accounts"}}} =
             render_click(view, "delete_account")

    refute Repo.get(Account, account.id)
  end

  test "marks an account as not an account and redirects to the accounts list", %{conn: conn} do
    user = insert_user!("non-account-marker@example.com")

    account =
      insert_account!(%{
        account_key: "operate:grafana",
        name: "Grafana Labs",
        primary_domain: "grafana.com",
        segment: :lead
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    assert has_element?(view, "#account-actions-dropdown")

    assert {:error, {:live_redirect, %{to: "/commercial/sales/accounts"}}} =
             render_click(view, "mark_not_account")

    stored = Repo.get!(Account, account.id)
    assert stored.not_an_account_at
    assert stored.not_an_account_reason == "Marked manually from the account page"
  end

  test "deleting an already removed account still redirects to the accounts list", %{conn: conn} do
    user = insert_user!("stale-deleter@example.com")

    account =
      insert_account!(%{
        account_key: "operate:stale_delete",
        name: "Stale Delete",
        segment: :prospect
      })

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/accounts/#{account.id}")

    assert {:ok, %Account{}} = Accounts.delete_account(account)

    assert has_element?(view, "#account-actions-dropdown")

    assert {:error, {:live_redirect, %{to: "/commercial/sales/accounts"}}} =
             render_click(view, "delete_account")
  end

  defp insert_user!(email, attrs \\ %{}) do
    {role, attrs} = Map.pop(attrs, :role)

    user =
      %User{}
      |> User.changeset(Map.merge(%{email: email, name: "Atlas User"}, attrs))
      |> Repo.insert!()

    if role == :executive do
      executive_role = Roles.ensure_executive_role!()

      %UserRole{}
      |> UserRole.changeset(%{user_id: user.id, role_id: executive_role.id})
      |> Repo.insert!()
    end

    user
  end

  defp insert_tax_certificate_account!(suffix) do
    insert_account!(%{
      account_key: "tax-certificate-account-#{suffix}",
      name: "Atlas GmbH #{suffix}",
      legal_name: "Atlas GmbH #{suffix}",
      segment: :customer,
      address: %{street: "Musterstraße 42", zip: "10115", city: "Berlin", country: "DE"},
      billing: %{tax_id: "30/123/45678"},
      signatory: %{name: "Mia Example", title: "Geschäftsführerin"}
    })
  end

  defp tax_certificate_attrs do
    %{
      "recipient_name" => "Finanzamt Berlin",
      "recipient_street" => "Musterstraße 1",
      "recipient_postal_code" => "10115",
      "recipient_city" => "Berlin",
      "foundation_date" => "2020-01-01",
      "legal_form" => "GmbH",
      "submission_to" => "Vergabestelle Berlin",
      "certificate_purpose" => "Teilnahme an einem Vergabeverfahren",
      "signing_location" => "Berlin"
    }
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

  defp insert_contact!(account, attrs) do
    defaults = %{
      full_name: "Contact",
      email: "contact#{System.unique_integer([:positive])}@example.com",
      notes: nil,
      account_id: account.id
    }

    %Contact{}
    |> Contact.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_account_handle!(account, attrs) do
    defaults = %{
      handle: "handle-#{System.unique_integer([:positive])}",
      source: "enterprise",
      account_id: account.id
    }

    %AccountHandle{}
    |> AccountHandle.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_invoice!(account, attrs) do
    defaults = %{
      external_id: "invoice:#{System.unique_integer([:positive])}",
      source: "enterprise",
      due_date: Date.utc_today()
    }

    %Invoice{account_id: account.id}
    |> Invoice.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_document!(account, attrs) do
    defaults = %{
      title: "Document",
      original_filename: "document.txt",
      content_type: "text/plain",
      byte_size: 10,
      checksum_sha256: "#{System.unique_integer([:positive])}",
      storage_bucket: "test-documents",
      storage_key: "documents/#{System.unique_integer([:positive])}.txt",
      status: "ready",
      source: "upload"
    }

    %Document{}
    |> Document.changeset(Map.merge(defaults, attrs))
    |> Ecto.Changeset.change(account_id: account.id)
    |> Repo.insert!()
  end

  defp insert_service_level_extraction_check!(account, document) do
    %ServiceLevelExtractionCheck{account_id: account.id, document_id: document.id}
    |> ServiceLevelExtractionCheck.changeset(%{
      agent_version: "service_level_extraction_agent:v1",
      document_checksum_sha256: document.checksum_sha256,
      status: "completed",
      started_at: ~U[2026-06-01 00:00:00Z],
      completed_at: ~U[2026-06-01 00:01:00Z]
    })
    |> Repo.insert!()
  end

  defp insert_service_level!(account, document, check, attrs) do
    defaults = %{
      name: "Availability",
      category: "availability",
      target: "99.9% uptime"
    }

    %ServiceLevel{
      account_id: account.id,
      document_id: document.id,
      service_level_extraction_check_id: check.id
    }
    |> ServiceLevel.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_account_attention_suggestion!(account) do
    %AccountAttentionSuggestion{account_id: account.id}
    |> AccountAttentionSuggestion.changeset(%{
      status: "pending",
      kind: "follow_up",
      suggestion_key: "follow_up:account-live-#{System.unique_integer([:positive])}",
      title: "Send the customer follow-up",
      rationale: "The account has an open follow-up to complete.",
      suggested_action: "Send a short status update.",
      evidence: %{
        "items" => [
          %{
            "source_type" => "account",
            "source_id" => account.id,
            "observation" => "The account has a current follow-up."
          }
        ]
      },
      confidence: Decimal.new("0.90"),
      generated_by_agent: "account_attention_agent"
    })
    |> Repo.insert!()
  end

  defp insert_event!(account, attrs) do
    defaults = %{
      external_id: "event:#{System.unique_integer([:positive])}",
      source: "operate",
      kind: "deal",
      title: "Imported event",
      occurred_at: ~U[2026-05-01 10:00:00Z],
      account_id: account.id
    }

    %Event{}
    |> Event.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp staged_screenshot_id(data) do
    hash =
      :crypto.hash(:sha256, data)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    "screenshot-#{hash}"
  end
end
