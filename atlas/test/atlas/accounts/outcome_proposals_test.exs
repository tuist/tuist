defmodule Atlas.Accounts.OutcomeProposalsTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Agents.OutcomeProposalAgent
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.Outcome
  alias Atlas.Accounts.OutcomeReview
  alias Atlas.Audit.Activity
  alias Atlas.Evidence
  alias Atlas.Repo
  alias Atlas.Users.User

  test "creates and approves a proposed outcome without affecting health before approval" do
    user = insert_user!()
    account = insert_account!()
    event = insert_event!(account, "Customer wants thirty weekly active developers by September.")

    assert {:ok, proposal} =
             Accounts.create_outcome_proposal(account, new_outcome_attrs(event))

    assert proposal.status == "pending"
    assert Accounts.list_active_outcomes(account) == []

    assert {:ok, %{proposal: approved, outcome: outcome}} =
             Accounts.approve_outcome_proposal(proposal, user)

    assert approved.status == "approved"
    assert approved.reviewed_by_id == user.id
    assert outcome.title == "Reach weekly adoption target"
    assert outcome.motion == "adoption"
    assert outcome.source_event_id == event.id
    assert outcome.owner_id == user.id
    assert outcome.metadata["proposal_id"] == proposal.id
  end

  test "edits and approves an evidence-based review proposal" do
    user = insert_user!()
    account = insert_account!()
    event = insert_event!(account, "Weekly active developers increased from twelve to eighteen.")
    outcome = insert_outcome!(account)

    {:ok, proposal} =
      Accounts.create_outcome_proposal(account, %{
        proposal_type: "outcome_review",
        outcome_id: outcome.id,
        health: "at_risk",
        summary: "Adoption improved, but remains below the agreed trajectory.",
        recommendation: "Review the delayed rollout with the second team.",
        rationale: "The latest usage evidence changes the health assessment.",
        confidence: "0.91",
        evidence: %{
          "items" => [%{"event_id" => event.id, "observation" => "Usage rose to eighteen."}]
        },
        generated_by_agent: "outcome_proposal_agent"
      })

    assert {:ok, edited} =
             Accounts.update_outcome_proposal(
               proposal,
               %{recommendation: "Pair with the delayed team on its rollout."},
               user
             )

    assert {:ok, %{proposal: approved, review: review, outcome: updated_outcome}} =
             Accounts.approve_outcome_proposal(edited, user)

    assert approved.status == "approved"
    assert review.author_id == user.id
    assert review.created_by_agent == "outcome_proposal_agent"
    assert review.recommendation == "Pair with the delayed team on its rollout."
    assert updated_outcome.health == "at_risk"
    assert Repo.aggregate(OutcomeReview, :count) == 1
  end

  test "approves a review whose cited event no longer exists" do
    user = insert_user!()
    account = insert_account!()
    event = insert_event!(account, "Weekly active developers increased from twelve to eighteen.")
    outcome = insert_outcome!(account)

    {:ok, proposal} =
      Accounts.create_outcome_proposal(account, %{
        proposal_type: "outcome_review",
        outcome_id: outcome.id,
        health: "at_risk",
        summary: "Adoption improved, but remains below the agreed trajectory.",
        recommendation: "Review the delayed rollout with the second team.",
        rationale: "The latest usage evidence changes the health assessment.",
        confidence: "0.91",
        evidence: %{
          "items" => [%{"event_id" => event.id, "observation" => "Usage rose to eighteen."}]
        },
        generated_by_agent: "outcome_proposal_agent"
      })

    Repo.delete!(event)

    assert {:ok, %{proposal: approved, review: review, outcome: updated_outcome}} =
             Accounts.approve_outcome_proposal(proposal, user)

    assert approved.status == "approved"
    assert updated_outcome.health == "at_risk"
    assert Evidence.for_subject("account_outcome_review", review.id) == []
  end

  test "rejects a proposal with feedback and leaves outcomes unchanged" do
    user = insert_user!()
    account = insert_account!()
    event = insert_event!(account, "Customer mentioned a possible future rollout.")
    {:ok, proposal} = Accounts.create_outcome_proposal(account, new_outcome_attrs(event))

    assert {:error, changeset} = Accounts.reject_outcome_proposal(proposal, "   ", user)
    assert "can't be blank" in errors_on(changeset).rejection_reason

    assert {:ok, rejected} =
             Accounts.reject_outcome_proposal(
               proposal,
               "This is an internal follow-up, not a customer outcome.",
               user
             )

    assert rejected.status == "rejected"
    assert rejected.reviewed_by_id == user.id
    assert rejected.rejection_reason =~ "not a customer outcome"
    assert Accounts.list_active_outcomes(account) == []
  end

  test "does not allow evidence or outcomes from another account" do
    account = insert_account!(%{account_key: "account:first", name: "First"})
    other = insert_account!(%{account_key: "account:other", name: "Other"})
    event = insert_event!(account, "First account evidence.")
    other_event = insert_event!(other, "Other account evidence.")
    other_outcome = insert_outcome!(other)

    assert {:error, changeset} =
             Accounts.create_outcome_proposal(account, %{
               proposal_type: "outcome_review",
               outcome_id: other_outcome.id,
               health: "off_track",
               summary: "This should not be accepted.",
               rationale: "Cross-account evidence must be rejected.",
               confidence: "0.99",
               evidence: %{
                 "items" => [%{"event_id" => other_event.id, "observation" => "Wrong account."}]
               },
               generated_by_agent: "outcome_proposal_agent"
             })

    assert "must belong to the account" in errors_on(changeset).outcome_id
    assert "must reference events from the account" in errors_on(changeset).evidence

    {:ok, proposal} = Accounts.create_outcome_proposal(account, new_outcome_attrs(event))

    assert {:error, update_changeset} =
             Accounts.update_outcome_proposal(proposal, %{
               evidence: %{
                 "items" => [%{"event_id" => other_event.id, "observation" => "Wrong account."}]
               }
             })

    assert "must reference events from the account" in errors_on(update_changeset).evidence
  end

  test "deduplicates pending proposals while allowing a new suggestion after rejection" do
    account = insert_account!()
    event = insert_event!(account, "Customer wants thirty weekly active developers by September.")
    attrs = new_outcome_attrs(event)

    assert {:ok, first} = Accounts.create_outcome_proposal(account, attrs)
    assert {:error, duplicate} = Accounts.create_outcome_proposal(account, attrs)
    assert "has already been taken" in errors_on(duplicate).proposal_key

    assert {:ok, _rejected} = Accounts.reject_outcome_proposal(first, "Needs a clearer target.")
    assert {:ok, second} = Accounts.create_outcome_proposal(account, attrs)
    assert second.id != first.id
  end

  test "generation persists only grounded high-confidence proposals and marks the account checked" do
    account = insert_account!()
    event = insert_event!(account, "Customer wants thirty weekly active developers by September.")

    expect(OutcomeProposalAgent, :propose, fn loaded_account ->
      assert loaded_account.id == account.id

      {:ok,
       %{
         "proposals" => [
           Map.merge(stringify_keys(new_outcome_attrs(event)), %{
             "proposal_type" => "new_outcome",
             "confidence" => "0.92",
             "evidence" => [
               %{"event_id" => event.id, "observation" => "The target is explicit."}
             ]
           }),
           %{
             "proposal_type" => "new_outcome",
             "title" => "Low confidence",
             "motion" => "adoption",
             "confidence" => "0.40",
             "rationale" => "Weak signal.",
             "evidence" => [
               %{"event_id" => event.id, "observation" => "Tentative mention."}
             ]
           }
         ]
       }}
    end)

    assert {:ok, [proposal]} = Accounts.generate_outcome_proposals(account.id)
    assert proposal.title == "Reach weekly adoption target"
    assert Repo.get!(Account, account.id).outcome_proposals_checked_at

    generation_activity =
      Repo.get_by!(Activity,
        action: "account_outcome_proposals.generated",
        target_id: account.id
      )

    assert generation_activity.metadata["created_count"] == 1
  end

  test "generation requires new evidence before repeating a rejected suggestion" do
    account = insert_account!()
    old_event = insert_event!(account, "Customer mentioned a possible rollout.")
    attrs = new_outcome_attrs(old_event)
    {:ok, proposal} = Accounts.create_outcome_proposal(account, attrs)
    {:ok, _rejected} = Accounts.reject_outcome_proposal(proposal, "The mention was hypothetical.")

    expect(OutcomeProposalAgent, :propose, fn _account ->
      {:ok, generated_result(attrs, old_event)}
    end)

    assert {:ok, []} = Accounts.generate_outcome_proposals(account.id)

    new_event = insert_event!(account, "Customer confirmed the rollout target and deadline.")

    expect(OutcomeProposalAgent, :propose, fn _account ->
      {:ok, generated_result(attrs, new_event)}
    end)

    assert {:ok, [reconsidered]} = Accounts.generate_outcome_proposals(account.id)
    assert reconsidered.proposal_key == proposal.proposal_key
    assert reconsidered.source_event_id == new_event.id
  end

  test "candidate selection includes new evidence and stale reviews but not a freshly checked account" do
    now = ~U[2026-07-16 08:00:00Z]

    new_evidence =
      insert_account!(%{
        account_key: "account:new-evidence",
        name: "New Evidence",
        outcome_proposals_checked_at: DateTime.add(now, -2, :day),
        latest_activity_at: DateTime.add(now, -1, :day)
      })

    stale_review =
      insert_account!(%{
        account_key: "account:stale-review",
        name: "Stale Review",
        outcome_proposals_checked_at: now,
        latest_activity_at: DateTime.add(now, -2, :day)
      })

    _stale_outcome =
      insert_outcome!(stale_review, %{reviewed_at: DateTime.add(now, -20, :day)})

    fresh =
      insert_account!(%{
        account_key: "account:fresh",
        name: "Fresh",
        outcome_proposals_checked_at: now,
        latest_activity_at: DateTime.add(now, -1, :day)
      })

    fresh
    |> Ecto.Changeset.change(%{updated_at: DateTime.to_naive(DateTime.add(now, -1, :day))})
    |> Repo.update!()

    ids = Accounts.list_outcome_proposal_candidate_ids(now: now)
    assert new_evidence.id in ids
    assert stale_review.id in ids
    refute fresh.id in ids
  end

  defp new_outcome_attrs(event) do
    %{
      proposal_type: "new_outcome",
      title: "Reach weekly adoption target",
      motion: "adoption",
      description: "The customer wants broader weekly use.",
      success_measure: "Weekly active developers",
      baseline: "12",
      target: "30",
      target_date: ~D[2026-09-30],
      rationale: "The customer stated a measurable adoption result.",
      confidence: "0.92",
      evidence: %{
        "items" => [%{"event_id" => event.id, "observation" => "The customer stated the target."}]
      },
      generated_by_agent: "outcome_proposal_agent"
    }
  end

  defp generated_result(attrs, event) do
    %{
      "proposals" => [
        attrs
        |> stringify_keys()
        |> Map.put("proposal_type", "new_outcome")
        |> Map.put("confidence", "0.92")
        |> Map.put("evidence", [
          %{"event_id" => event.id, "observation" => "The customer supplied explicit evidence."}
        ])
      ]
    }
  end

  defp insert_account!(attrs \\ %{}) do
    {outcome_proposals_checked_at, attrs} = Map.pop(attrs, :outcome_proposals_checked_at)

    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Northstar",
      segment: :customer
    }

    %Account{outcome_proposals_checked_at: outcome_proposals_checked_at}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_event!(account, body) do
    %Event{}
    |> Event.changeset(%{
      account_id: account.id,
      external_id: "event:#{System.unique_integer([:positive])}",
      source: "atlas",
      kind: "note",
      title: "Outcome evidence",
      body: body,
      occurred_at: ~U[2026-07-15 10:00:00Z]
    })
    |> Repo.insert!()
  end

  defp insert_outcome!(account, attrs \\ %{}) do
    defaults = %{
      account_id: account.id,
      title: "Reach adoption target",
      motion: "adoption",
      status: "active",
      health: "on_track",
      success_measure: "Weekly active developers"
    }

    %Outcome{account_id: account.id}
    |> Outcome.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_user! do
    %User{}
    |> User.changeset(%{
      email: "reviewer-#{System.unique_integer([:positive])}@example.com",
      name: "Reviewer",
      role: :executive
    })
    |> Repo.insert!()
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
