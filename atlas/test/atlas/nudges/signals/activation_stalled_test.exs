defmodule Atlas.Nudges.Signals.ActivationStalledTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Nudges.Analytics.FeatureFirstSeen
  alias Atlas.Nudges.Analytics.MetricBucket
  alias Atlas.Nudges.Proposal
  alias Atlas.Nudges.Signals.ActivationStalled
  alias Atlas.Repo

  test "fires when the account is measurable but no feature has ever been seen" do
    account = insert_account_backdated!(20)
    insert_ok_bucket!(account)

    assert {:ok, %Proposal{} = proposal} = ActivationStalled.evaluate(account)
    assert proposal.title =~ "no Tuist activity"
  end

  test "skips when any feature has already been seen" do
    account = insert_account_backdated!(20)
    insert_ok_bucket!(account)
    insert_first_seen!(account, "cache")

    assert :skip = ActivationStalled.evaluate(account)
  end

  test "suppresses when the account has no successful measurement (couldn't resolve)" do
    account = insert_account_backdated!(20)
    # No metric buckets at all → we treat this as "could not measure."
    assert :skip = ActivationStalled.evaluate(account)
  end

  defp insert_account_backdated!(days_ago) do
    old = NaiveDateTime.utc_now() |> NaiveDateTime.add(-days_ago, :day) |> NaiveDateTime.truncate(:second)

    %Account{}
    |> Account.changeset(%{
      account_key: "activation:#{System.unique_integer([:positive])}",
      name: "Silent Customer",
      segment: :customer,
      plan_tier: "pro"
    })
    |> Repo.insert!()
    |> Ecto.Changeset.change(inserted_at: old, updated_at: old)
    |> Repo.update!()
  end

  defp insert_ok_bucket!(account) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %MetricBucket{}
    |> MetricBucket.changeset(%{
      account_id: account.id,
      bucket_date: Date.utc_today() |> Date.add(-1),
      refresh_status: "ok",
      computed_at: now
    })
    |> Repo.insert!()
  end

  defp insert_first_seen!(account, feature) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %FeatureFirstSeen{}
    |> FeatureFirstSeen.changeset(%{
      account_id: account.id,
      feature: feature,
      first_use_at: now,
      first_seen_computed_at: now
    })
    |> Repo.insert!()
  end
end
