defmodule Atlas.Nudges.Signals.FirstCacheEventTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Nudges.Analytics.FeatureFirstSeen
  alias Atlas.Nudges.Proposal
  alias Atlas.Nudges.Signals.FirstCacheEvent
  alias Atlas.Repo

  test "fires when a fresh first-seen row landed within the window" do
    account = insert_account!()
    insert_first_seen!(account, "cache", fresh: true)

    assert {:ok, %Proposal{} = proposal} = FirstCacheEvent.evaluate(account)
    assert proposal.title =~ "first cache activity"
  end

  test "skips when the first-seen row is older than the freshness window" do
    account = insert_account!()
    insert_first_seen!(account, "cache", fresh: false)

    assert :skip = FirstCacheEvent.evaluate(account)
  end

  test "skips when no first-seen row exists" do
    account = insert_account!()
    assert :skip = FirstCacheEvent.evaluate(account)
  end

  defp insert_account! do
    %Account{}
    |> Account.changeset(%{
      account_key: "first-cache:#{System.unique_integer([:positive])}",
      name: "First Cache Customer",
      segment: :customer,
      plan_tier: "pro"
    })
    |> Repo.insert!()
  end

  defp insert_first_seen!(account, feature, fresh: fresh) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    computed_at =
      if fresh, do: now, else: DateTime.add(now, -96, :hour) |> DateTime.truncate(:second)

    %FeatureFirstSeen{}
    |> FeatureFirstSeen.changeset(%{
      account_id: account.id,
      feature: feature,
      first_use_at: now,
      first_seen_computed_at: computed_at
    })
    |> Repo.insert!()
  end
end
