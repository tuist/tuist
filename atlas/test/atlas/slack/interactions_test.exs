defmodule Atlas.Slack.InteractionsTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Outreach.Recommendation
  alias Atlas.Outreach.RecommendationNotifier
  alias Atlas.Repo
  alias Atlas.Slack.API
  alias Atlas.Slack.Interactions
  alias Atlas.Users.User

  setup :verify_on_exit!

  test "ignores unsupported payloads and actions from non-company Slack workspace keys" do
    assert {:ok, "Slack action ignored."} = Interactions.handle_interaction(%{"type" => "view_submission"}, :company)

    payload = %{
      "type" => "block_actions",
      "actions" => [
        %{"action_id" => "gtm_opportunity:review", "value" => Ecto.UUID.generate()}
      ]
    }

    assert {:ok, "Slack action ignored."} = Interactions.handle_interaction(payload, :community)
  end

  test "maps missing GTM opportunity actions to a Slack-friendly error" do
    payload = %{
      "type" => "block_actions",
      "actions" => [
        %{"action_id" => "gtm_opportunity:review", "value" => Ecto.UUID.generate()}
      ]
    }

    assert {:error, "GTM opportunity not found."} = Interactions.handle_interaction(payload, :company)
  end

  test "completes an outreach recommendation from Slack and refreshes its blocks" do
    user =
      %User{}
      |> User.changeset(%{email: "sales-reviewer@tuist.dev", name: "Sales Reviewer"})
      |> Repo.insert!()

    account =
      %Account{}
      |> Account.changeset(%{
        account_key: "slack-outreach:#{System.unique_integer([:positive])}",
        name: "Acme Platforms",
        segment: :prospect
      })
      |> Repo.insert!()

    contact =
      %Contact{account_id: account.id}
      |> Contact.outreach_changeset(%{
        full_name: "Jordan Lee",
        email: "jordan-slack@example.com",
        linkedin_url: "https://www.linkedin.com/in/jordan-slack",
        outreach_enrolled_at: ~U[2026-07-20 09:00:00Z],
        outreach_status: "connected"
      })
      |> Repo.insert!()

    event =
      %Event{account_id: account.id, contact_id: contact.id}
      |> Event.changeset(%{
        external_id: "slack-evidence",
        source: "linkedin",
        kind: "connection_accepted",
        title: "Connection accepted",
        occurred_at: ~U[2026-07-20 10:00:00Z]
      })
      |> Repo.insert!()

    recommendation =
      %Recommendation{
        contact_id: contact.id,
        account_id: account.id,
        source_event_id: event.id,
        slack_notification_requested_at: ~U[2026-07-20 10:01:00Z]
      }
      |> Recommendation.changeset(%{
        status: "pending",
        action_type: "message",
        recommended_event_kind: "message_sent",
        title: "Ask one relevant question",
        guidance: "Ask about the engineering workflow.",
        rationale: "The connection is accepted.",
        draft_message: "Which part of the workflow is creating the most friction?",
        due_at: ~U[2026-07-20 12:00:00Z],
        confidence: Decimal.new("0.90"),
        evidence: %{"items" => [%{"event_id" => event.id, "observation" => event.title}]},
        generated_by_agent: "outreach_recommendation_agent"
      })
      |> Ecto.Changeset.change(%{
        slack_notification_posted_at: ~U[2026-07-20 10:01:30Z],
        slack_notification_channel_id: "C_SALES",
        slack_notification_thread_ts: "1717400000.000100"
      })
      |> Repo.insert!()

    expect(API, :update_message, fn :company, "C_SALES", "1717400000.000100", text, blocks ->
      assert text =~ "Jordan Lee"
      rendered = Jason.encode!(blocks)
      assert rendered =~ "Completed"
      refute rendered =~ "Mark done"
      {:ok, %{"ok" => true}}
    end)

    payload = %{
      "type" => "block_actions",
      "container" => %{"channel_id" => "C_SALES"},
      "user" => %{"name" => "sales-reviewer", "profile" => %{"email" => user.email}},
      "actions" => [
        %{
          "action_id" => RecommendationNotifier.action_id("complete"),
          "value" => recommendation.id
        }
      ]
    }

    assert {:ok, "Next step marked complete."} = Interactions.handle_interaction(payload, :company)
    assert Repo.get!(Recommendation, recommendation.id).status == "completed"
    assert Repo.get!(Recommendation, recommendation.id).reviewed_by_id == user.id
  end
end
