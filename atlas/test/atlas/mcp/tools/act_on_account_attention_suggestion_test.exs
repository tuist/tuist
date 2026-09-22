defmodule Atlas.MCP.Tools.ActOnAccountAttentionSuggestionTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Accounts.AccountAttentionSuggestion
  alias Atlas.MCP.Tools.ActOnAccountAttentionSuggestion
  alias Atlas.Repo

  test "snoozes, completes, and dismisses account attention suggestions" do
    account = insert_account!(%{name: "Attention Account", segment: :customer})
    suggestion = insert_suggestion!(account, "snooze-and-complete")

    assert {:ok, snoozed} =
             execute_tool(ActOnAccountAttentionSuggestion, nil, %{
               "suggestion_id" => suggestion.id,
               "action" => "snooze",
               "snooze_days" => 14,
               "note" => "Wait for the renewal planning meeting."
             })

    assert snoozed.status == "snoozed"
    assert snoozed.snoozed_until
    assert snoozed.resolution_note == "Wait for the renewal planning meeting."

    assert {:ok, actioned} =
             execute_tool(ActOnAccountAttentionSuggestion, nil, %{
               "suggestion_id" => suggestion.id,
               "action" => "done",
               "note" => "The follow-up was sent."
             })

    assert actioned.status == "actioned"
    assert actioned.resolution_note == "The follow-up was sent."

    dismissed = insert_suggestion!(account, "dismiss")

    assert {:ok, dismissed} =
             execute_tool(ActOnAccountAttentionSuggestion, nil, %{
               "suggestion_id" => dismissed.id,
               "action" => "dismiss",
               "note" => "The account already has an owner."
             })

    assert dismissed.status == "dismissed"
    assert Repo.get!(AccountAttentionSuggestion, dismissed.id).resolution_note == "The account already has an owner."
  end

  test "rejects an invalid snooze duration" do
    account = insert_account!(%{name: "Attention Account", segment: :customer})
    suggestion = insert_suggestion!(account, "invalid-snooze")

    assert {:error, "Could not update the account attention suggestion: :invalid_snooze_days"} =
             execute_tool(ActOnAccountAttentionSuggestion, nil, %{
               "suggestion_id" => suggestion.id,
               "action" => "snooze",
               "snooze_days" => 0
             })
  end

  defp insert_suggestion!(account, topic) do
    %AccountAttentionSuggestion{account_id: account.id}
    |> AccountAttentionSuggestion.changeset(%{
      status: "pending",
      kind: "follow_up",
      suggestion_key: "follow_up:#{topic}-#{System.unique_integer([:positive])}",
      title: "Follow up about #{topic}",
      rationale: "The account has a timely follow-up to complete.",
      suggested_action: "Send the follow-up message.",
      evidence: %{
        "items" => [
          %{
            "source_type" => "account",
            "source_id" => account.id,
            "observation" => "The account is configured for a follow-up."
          }
        ]
      },
      confidence: Decimal.new("0.90"),
      generated_by_agent: "account_attention_agent"
    })
    |> Repo.insert!()
  end
end
