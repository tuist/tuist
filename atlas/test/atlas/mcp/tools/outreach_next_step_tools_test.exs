defmodule Atlas.MCP.Tools.OutreachNextStepToolsTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Accounts.Contact
  alias Atlas.MCP.Tools.CompleteOutreachNextStep
  alias Atlas.MCP.Tools.DismissOutreachNextStep
  alias Atlas.MCP.Tools.GenerateOutreachNextStep
  alias Atlas.MCP.Tools.GetOutreachNextStep
  alias Atlas.Outreach.Agents.RecommendationAgent
  alias Atlas.Outreach.Recommendation
  alias Atlas.Repo

  setup :verify_on_exit!

  test "generates, reads, and dismisses an outreach next step" do
    user = insert_user!()
    account = insert_account!(%{name: "Acme Platforms", segment: :prospect})

    contact =
      insert_contact!(account, %{
        full_name: "Jordan Lee",
        outreach_enrolled_at: ~U[2026-07-20 09:00:00Z],
        outreach_status: "replied"
      })

    event =
      insert_event!(account, %{
        contact_id: contact.id,
        source: "linkedin",
        kind: "message_received",
        title: "Message received",
        body: "Trust in the feedback is the hard part."
      })

    expect(RecommendationAgent, :recommend, fn _context -> {:ok, generated_result(event)} end)

    assert {:ok, %{recommendation: generated}} =
             execute_tool(GenerateOutreachNextStep, mcp_conn(user), %{"contact_id" => contact.id})

    assert generated.action_type == "inmail"
    assert generated.draft_subject == "Trust in build feedback"
    assert generated.draft_message =~ "decide"

    assert {:ok, %{recommendation: current}} =
             execute_tool(GetOutreachNextStep, mcp_conn(user), %{"contact_id" => contact.id})

    assert current.id == generated.id

    assert {:ok, %{recommendation: dismissed}} =
             execute_tool(DismissOutreachNextStep, mcp_conn(user), %{
               "recommendation_id" => generated.id,
               "reason" => "The question is too generic."
             })

    assert dismissed.status == "dismissed"
    assert dismissed.review_reason == "The question is too generic."
  end

  test "completes a suggestion and records the draft in history" do
    user = insert_user!()
    account = insert_account!(%{name: "Acme Platforms", segment: :prospect})

    contact =
      insert_contact!(account, %{
        outreach_enrolled_at: ~U[2026-07-20 09:00:00Z],
        outreach_status: "connected"
      })

    evidence = insert_event!(account, %{contact_id: contact.id, body: "Connection accepted."})
    recommendation = insert_recommendation!(contact, evidence)

    assert {:ok, %{recommendation: completed}} =
             execute_tool(CompleteOutreachNextStep, mcp_conn(user), %{
               "recommendation_id" => recommendation.id
             })

    assert completed.status == "completed"
    assert Repo.get!(Contact, contact.id).outreach_status == "conversation_started"
  end

  defp insert_recommendation!(contact, event) do
    %Recommendation{contact_id: contact.id, account_id: contact.account_id, source_event_id: event.id}
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
      evidence: %{"items" => [%{"event_id" => event.id, "observation" => event.body}]},
      generated_by_agent: "outreach_recommendation_agent"
    })
    |> Repo.insert!()
  end

  defp generated_result(event) do
    %{
      "recommendations" => [
        %{
          "action_type" => "inmail",
          "title" => "Explore how the team builds trust",
          "guidance" => "Reflect the concern and ask one question.",
          "rationale" => "Jordan offered a specific challenge.",
          "draft_subject" => "Trust in build feedback",
          "draft_message" => "How does your team decide which feedback engineers will trust?",
          "due_in_days" => 0,
          "confidence" => "0.91",
          "personalization_basis" => "Jordan's reply about trust",
          "message_intent" => "deepen_context",
          "personalization_source" => "recipient_message",
          "call_to_action" => "question",
          "risks" => [],
          "evidence" => [%{"event_id" => event.id, "observation" => event.body}]
        }
      ]
    }
  end
end
