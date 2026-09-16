defmodule Atlas.Accounts.FeatureInterestsTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Audit.Activity
  alias Atlas.Repo
  alias Atlas.Users.User

  test "groups the same requested capability across accounts and keeps timeline evidence" do
    first_account = insert_account!("First company")
    second_account = insert_account!("Second company")
    first_event = insert_event!(first_account, "First request")
    second_event = insert_event!(second_account, "Second request")

    assert {:ok, %{interest: interest}} =
             Accounts.record_feature_interest_from_event(
               first_event,
               %{
                 title: "Remote build runners",
                 summary: "They need managed runners for their release builds.",
                 notes: "Release planning is the immediate priority."
               }
             )

    assert {:ok, %{interest: second_interest}} =
             Accounts.record_feature_interest_from_event(
               second_event,
               %{title: " remote  BUILD runners ", summary: "They need isolated runners for pull request builds."}
             )

    assert second_interest.id == interest.id
    assert Accounts.list_feature_interests() |> Enum.map(& &1.id) == [interest.id]

    detail = Accounts.get_feature_interest(interest.id)
    assert detail.interest_count == 2

    assert Enum.map(detail.accounts, & &1.account.name) |> MapSet.new() ==
             MapSet.new([first_account.name, second_account.name])

    first_account_interest = Enum.find(detail.accounts, &(&1.account_id == first_account.id))

    assert first_account_interest.account_event_id == first_event.id
    assert first_account_interest.account_event.id == first_event.id
    assert first_account_interest.notes == "Release planning is the immediate priority."
    assert first_account_interest.summary == "They need managed runners for their release builds."

    assert [account_interest] = Accounts.list_feature_interests_for_account(first_account)
    assert account_interest.id == interest.id
    assert List.first(account_interest.accounts).account_event.id == first_event.id
  end

  test "requires a timeline event linked to an account" do
    event = %Event{account_id: nil}

    assert {:error, :account_required} =
             Accounts.record_feature_interest_from_event(
               event,
               %{title: "Remote build runners", summary: "They need managed runners for release builds."}
             )
  end

  test "audits the account and timeline event that supplied the request" do
    user = insert_user!()
    account = insert_account!("Audited company")
    event = insert_event!(account, "Audited request")

    assert {:ok, %{interest: interest}} =
             Accounts.record_feature_interest_from_event(
               event,
               %{title: "Artifact retention", summary: "They need release artifacts retained for audit reviews."},
               user
             )

    activity = Repo.get_by!(Activity, action: "feature_interest.recorded", target_id: interest.id)
    assert activity.actor_id == user.id
    assert activity.metadata["account_path"] == "/sales/accounts/#{account.id}"
    assert activity.metadata["account_event_path"] == "/sales/accounts/#{account.id}#timeline-event-#{event.id}"
  end

  test "updates account-specific notes and audits the change" do
    user = insert_user!()
    account = insert_account!("Notes company")
    event = insert_event!(account, "Notes request")

    assert {:ok, %{account_interest: interest_account}} =
             Accounts.record_feature_interest_from_event(
               event,
               %{title: "Artifact retention", summary: "They need retained release artifacts."}
             )

    assert {:ok, updated_interest_account} =
             Accounts.update_feature_interest_notes(
               interest_account,
               %{notes: "Security review makes this urgent."},
               user
             )

    assert updated_interest_account.notes == "Security review makes this urgent."

    activity =
      Repo.get_by!(
        Activity,
        action: "feature_interest.notes_updated",
        target_id: interest_account.feature_interest_id
      )

    assert activity.actor_id == user.id
    assert activity.metadata["account_event_id"] == event.id
  end

  defp insert_account!(name) do
    suffix = System.unique_integer([:positive])

    %Account{}
    |> Account.changeset(%{account_key: "account:feature-interest-#{suffix}", name: name, segment: :customer})
    |> Repo.insert!()
  end

  defp insert_event!(account, title) do
    suffix = System.unique_integer([:positive])

    %Event{account_id: account.id}
    |> Event.changeset(%{
      external_id: "feature-interest-event-#{suffix}",
      source: "granola",
      kind: "meeting",
      title: title,
      body: "Customer conversation transcript.",
      occurred_at: ~U[2026-08-26 10:00:00Z]
    })
    |> Repo.insert!()
  end

  defp insert_user! do
    suffix = System.unique_integer([:positive])

    %User{}
    |> User.changeset(%{email: "feature-interest-#{suffix}@tuist.dev", name: "Feature interest owner"})
    |> Repo.insert!()
  end
end
