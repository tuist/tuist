defmodule Atlas.MCP.Tools.OutcomeToolsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Accounts.Outcome
  alias Atlas.Accounts.OutcomeReview
  alias Atlas.MCP.Tools.CreateAccountOutcome
  alias Atlas.MCP.Tools.CreateOutcomeReview
  alias Atlas.MCP.Tools.ListAccountOutcomes
  alias Atlas.MCP.Tools.UpdateAccountOutcome
  alias Atlas.Repo

  test "creates, lists, reviews, and achieves an account outcome" do
    user = insert_user!()
    account = insert_account!(%{name: "Northstar", segment: :customer})
    conn = conn_for(user)

    assert {:ok, created} =
             execute_tool(CreateAccountOutcome, conn, %{
               "account_id" => account.id,
               "title" => "Reach weekly adoption target",
               "motion" => "adoption",
               "success_measure" => "Weekly active developers",
               "baseline" => "12",
               "target" => "30",
               "target_date" => "2026-08-31"
             })

    outcome = Repo.get!(Outcome, created.id)
    assert outcome.owner_id == user.id
    assert outcome.status == "active"
    assert outcome.health == "unknown"

    assert {:ok, %{outcomes: [listed], count: 1}} =
             execute_tool(ListAccountOutcomes, conn, %{
               "account_id" => account.id,
               "status" => "active"
             })

    assert listed.id == outcome.id

    assert {:ok, review} =
             execute_tool(CreateOutcomeReview, conn, %{
               "outcome_id" => outcome.id,
               "health" => "at_risk",
               "summary" => "Usage increased, but the second rollout slipped.",
               "evidence" => ["Weekly active developers rose from twelve to eighteen."],
               "recommendation" => "Pair with the delayed team on its first rollout."
             })

    assert review.health == "at_risk"
    assert Repo.get!(OutcomeReview, review.id).author_id == user.id
    assert Repo.get!(Outcome, outcome.id).health == "at_risk"

    assert {:ok, achieved} =
             execute_tool(UpdateAccountOutcome, conn, %{
               "outcome_id" => outcome.id,
               "status" => "achieved"
             })

    assert achieved.status == "achieved"
    assert achieved.achieved_at
  end
end
