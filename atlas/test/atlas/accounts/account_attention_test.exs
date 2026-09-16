defmodule Atlas.Accounts.AccountAttentionTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountAttentionSuggestion
  alias Atlas.Audit.Activity
  alias Atlas.Repo

  test "snoozes and then completes an account suggestion, retaining the resolution history" do
    account = insert_account!()
    suggestion = insert_suggestion!(account)
    until = ~U[2026-09-02 10:00:00Z]

    assert {:ok, snoozed} = Accounts.snooze_account_attention_suggestion(suggestion, until)
    assert snoozed.status == "snoozed"
    assert snoozed.snoozed_until == until

    assert {:ok, actioned} = Accounts.action_account_attention_suggestion(snoozed, "Sent a check-in.")
    assert actioned.status == "actioned"
    assert actioned.resolved_at
    assert actioned.resolution_note == "Sent a check-in."

    assert Repo.get_by!(Activity,
             action: "account_attention_suggestion.actioned",
             target_id: suggestion.id
           )
  end

  test "allows only one unresolved suggestion for the same account issue" do
    account = insert_account!()
    _suggestion = insert_suggestion!(account)

    assert {:error, changeset} =
             %AccountAttentionSuggestion{account_id: account.id}
             |> AccountAttentionSuggestion.changeset(suggestion_attrs())
             |> Repo.insert()

    assert "has already been taken" in errors_on(changeset).suggestion_key
  end

  defp insert_account! do
    %Account{}
    |> Account.changeset(%{
      account_key: "account:attention:#{System.unique_integer([:positive])}",
      name: "Acme",
      segment: :customer
    })
    |> Repo.insert!()
  end

  defp insert_suggestion!(account) do
    %AccountAttentionSuggestion{account_id: account.id}
    |> AccountAttentionSuggestion.changeset(suggestion_attrs())
    |> Repo.insert!()
  end

  defp suggestion_attrs do
    %{
      status: "pending",
      kind: "usage_change",
      suggestion_key: "usage_change:test-sharding-drop",
      title: "Check in about test sharding",
      rationale: "Test sharding use declined after being central to the delivery workflow.",
      suggested_action: "Ask whether the recent build workflow change caused the drop.",
      evidence: %{
        "items" => [
          %{
            "source_type" => "account",
            "source_id" => "account-context",
            "observation" => "The account has strategic delivery workflow guidance."
          }
        ]
      },
      confidence: "0.90",
      generated_by_agent: "account_attention_agent"
    }
  end
end
