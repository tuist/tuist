defmodule Atlas.Accounts.Briefs.AdapterTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Briefs.Adapter
  alias Atlas.Accounts.Event

  test "keeps matching proposal keys from different accounts as distinct traces" do
    first_account = insert_account!("First account")
    second_account = insert_account!("Second account")
    first_event = insert_event!(first_account)
    second_event = insert_event!(second_account)

    assert {:ok, first_proposal} =
             Accounts.create_outcome_proposal(first_account, proposal_attrs(first_event))

    assert {:ok, second_proposal} =
             Accounts.create_outcome_proposal(second_account, proposal_attrs(second_event))

    period = %{start_at: ~U[2026-07-20 00:00:00Z], end_at: ~U[2026-07-21 00:00:00Z]}
    assert {:ok, %{items: items}} = Adapter.candidate_items("daily", period)

    proposal_items =
      Enum.filter(items, &(&1.source_id in [first_proposal.id, second_proposal.id]))

    assert length(proposal_items) == 2
    assert proposal_items |> Enum.map(& &1.fingerprint) |> Enum.uniq() |> length() == 2
  end

  defp insert_account!(name) do
    %Account{}
    |> Account.changeset(%{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: name,
      segment: :customer
    })
    |> Repo.insert!()
  end

  defp insert_event!(account) do
    %Event{}
    |> Event.changeset(%{
      account_id: account.id,
      external_id: "event:#{System.unique_integer([:positive])}",
      source: "atlas",
      kind: "note",
      title: "Outcome evidence",
      body: "The customer confirmed an adoption target.",
      occurred_at: ~U[2026-07-20 10:00:00Z]
    })
    |> Repo.insert!()
  end

  defp proposal_attrs(event) do
    %{
      proposal_type: "new_outcome",
      title: "Reach weekly adoption target",
      motion: "adoption",
      rationale: "The customer stated a measurable adoption result.",
      confidence: "0.92",
      evidence: %{
        "items" => [%{"event_id" => event.id, "observation" => "The customer stated the target."}]
      },
      generated_by_agent: "outcome_proposal_agent"
    }
  end
end
