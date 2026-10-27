defmodule Atlas.Outreach.RecommendationNotifierTest do
  use ExUnit.Case, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Outreach.Recommendation
  alias Atlas.Outreach.RecommendationNotifier

  test "builds a guided Slack message with review controls and a safety boundary" do
    blocks = RecommendationNotifier.build_blocks(recommendation())
    rendered = JSON.encode!(blocks)

    assert rendered =~ "Next step: Jordan Lee"
    assert rendered =~ "Explore how the team builds trust"
    assert rendered =~ "Suggested draft"
    assert rendered =~ "Trust in build feedback"
    assert rendered =~ "Why now"
    assert rendered =~ "Mark done"
    assert rendered =~ "Try another"
    assert rendered =~ "Dismiss"
    assert rendered =~ "Open LinkedIn"
    assert rendered =~ "never sends LinkedIn invitations or messages automatically"
  end

  test "removes action controls after review" do
    rendered =
      recommendation() |> Map.put(:status, "dismissed") |> RecommendationNotifier.build_blocks() |> JSON.encode!()

    refute rendered =~ "Mark done"
    refute rendered =~ "Try another"
    assert rendered =~ "Dismissed"
  end

  defp recommendation do
    account = %Account{id: Ecto.UUID.generate(), name: "Acme Platforms"}

    contact = %Contact{
      id: Ecto.UUID.generate(),
      account_id: account.id,
      account: account,
      full_name: "Jordan Lee",
      title: "Director of Developer Productivity",
      linkedin_url: "https://www.linkedin.com/in/jordan-lee"
    }

    %Recommendation{
      id: Ecto.UUID.generate(),
      contact_id: contact.id,
      account_id: account.id,
      contact: contact,
      account: account,
      status: "pending",
      action_type: "inmail",
      title: "Explore how the team builds trust",
      guidance: "Reflect the concern and ask one question.",
      rationale: "Jordan offered a specific challenge.",
      draft_subject: "Trust in build feedback",
      draft_message: "How does your team decide which feedback engineers will trust?",
      due_at: ~U[2026-07-20 12:00:00Z],
      confidence: Decimal.new("0.91"),
      evidence: %{
        "items" => [
          %{"event_id" => Ecto.UUID.generate(), "observation" => "Jordan described a trust problem."}
        ]
      }
    }
  end
end
