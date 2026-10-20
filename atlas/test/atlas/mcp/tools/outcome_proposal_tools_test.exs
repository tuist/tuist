defmodule Atlas.MCP.Tools.OutcomeProposalToolsTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Accounts
  alias Atlas.Accounts.Agents.OutcomeProposalAgent
  alias Atlas.Accounts.Outcome
  alias Atlas.MCP.Tools.ApproveAccountOutcomeProposal
  alias Atlas.MCP.Tools.GenerateAccountOutcomeProposals
  alias Atlas.MCP.Tools.ListAccountOutcomeProposals
  alias Atlas.MCP.Tools.RejectAccountOutcomeProposal
  alias Atlas.MCP.Tools.UpdateAccountOutcomeProposal
  alias Atlas.Repo

  test "generates, edits, lists, and approves a grounded proposal" do
    user = insert_user!()
    account = insert_account!(%{name: "Northstar", segment: :customer})
    event = insert_event!(account, %{body: "The customer wants forty weekly active developers by September."})
    conn = conn_for(user)

    expect(OutcomeProposalAgent, :propose, fn loaded_account ->
      assert loaded_account.id == account.id

      {:ok,
       %{
         "proposals" => [
           %{
             "proposal_type" => "new_outcome",
             "title" => "Reach weekly adoption target",
             "description" => "Make the rollout repeatable across the mobile organization.",
             "motion" => "adoption",
             "success_measure" => "Weekly active developers",
             "baseline" => "18 developers",
             "target" => "40 developers",
             "target_date" => "2026-09-30",
             "confidence" => "0.93",
             "rationale" => "The customer named a measurable result and deadline.",
             "evidence" => [
               %{
                 "event_id" => event.id,
                 "observation" => "The customer set forty weekly active developers as the target."
               }
             ]
           }
         ]
       }}
    end)

    assert {:ok, %{proposals: [generated], count: 1}} =
             execute_tool(GenerateAccountOutcomeProposals, conn, %{"account_id" => account.id})

    assert generated.status == "pending"
    assert generated.confidence == "0.93"

    assert {:ok, edited} =
             execute_tool(UpdateAccountOutcomeProposal, conn, %{
               "proposal_id" => generated.id,
               "title" => "Reach weekly product adoption",
               "target" => "45 developers"
             })

    assert edited.title == "Reach weekly product adoption"
    assert edited.target == "45 developers"

    assert {:ok, %{proposals: [listed], count: 1}} =
             execute_tool(ListAccountOutcomeProposals, conn, %{
               "account_id" => account.id,
               "status" => "pending"
             })

    assert listed.id == generated.id

    assert {:ok, approved} =
             execute_tool(ApproveAccountOutcomeProposal, conn, %{"proposal_id" => generated.id})

    outcome = Repo.get_by!(Outcome, account_id: account.id, title: "Reach weekly product adoption")
    assert approved.status == "approved"
    assert approved.outcome_id == outcome.id
    assert outcome.owner_id == user.id
  end

  test "rejects a proposal with durable reviewer feedback" do
    user = insert_user!()
    account = insert_account!(%{name: "Northstar", segment: :customer})
    event = insert_event!(account, %{body: "A customer mentioned a possible rollout."})
    conn = conn_for(user)

    {:ok, proposal} =
      Accounts.create_outcome_proposal(account, %{
        proposal_type: "new_outcome",
        title: "Expand to another team",
        motion: "expansion",
        evidence: %{
          "items" => [
            %{"event_id" => event.id, "observation" => "A possible rollout was mentioned."}
          ]
        },
        confidence: "0.81",
        rationale: "The mention may indicate expansion intent.",
        generated_by_agent: "outcome_proposal_agent"
      })

    assert {:ok, rejected} =
             execute_tool(RejectAccountOutcomeProposal, conn, %{
               "proposal_id" => proposal.id,
               "reason" => "This was hypothetical and had no customer commitment."
             })

    assert rejected.status == "rejected"
    assert rejected.rejection_reason == "This was hypothetical and had no customer commitment."
    assert rejected.reviewed_at
  end
end
