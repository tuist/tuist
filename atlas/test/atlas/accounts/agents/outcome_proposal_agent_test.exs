defmodule Atlas.Accounts.Agents.OutcomeProposalAgentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Accounts.Agents.OutcomeProposalAgent
  alias Atlas.LLMs

  test "returns an error when no language model is configured" do
    stub(LLMs, :config, fn -> nil end)

    account = %{
      id: Atlas.UUIDv7.generate(),
      name: "Northstar",
      segment: :customer,
      status: "active",
      deal_stage: "closed_won",
      description: nil,
      next_renewal_date: nil,
      poc_end_date: nil,
      outcomes: [],
      outcome_proposals: [],
      events: []
    }

    assert {:error, :llm_not_configured} = OutcomeProposalAgent.propose(account)
  end

  test "requires grounded proposals and distinguishes results from tasks" do
    prompt = OutcomeProposalAgent.system_prompt()

    assert prompt =~ "customer result"
    assert prompt =~ "not a company task"
    assert prompt =~ "timeline event identifiers"
    assert prompt =~ "reviewed by a person"
    assert prompt =~ "empty proposals list"
    assert prompt =~ "untrusted evidence"
  end
end
