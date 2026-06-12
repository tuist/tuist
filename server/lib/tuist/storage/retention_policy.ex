defmodule Tuist.Storage.RetentionPolicy do
  @moduledoc false

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Billing.Subscription
  alias Tuist.Repo

  @default_plan :air
  @known_plans [:air, :open_source, :pro, :enterprise]

  @retention_days %{
    cache_artifact: %{air: 14, open_source: 14, pro: 30, enterprise: 90},
    xcode_cache_artifact: %{air: 14, open_source: 14, pro: 30, enterprise: 90},
    preview_app_build: %{air: 60, open_source: 60, pro: 180, enterprise: 365},
    preview_icon: %{air: 60, open_source: 60, pro: 180, enterprise: 365},
    build_archive: %{air: 30, open_source: 30, pro: 90, enterprise: 365},
    test_attachment: %{air: 30, open_source: 30, pro: 90, enterprise: 365},
    shard_bundle: %{air: 7, open_source: 7, pro: 14, enterprise: 30}
  }

  def current_plan(%Account{} = account) do
    case Billing.get_current_active_subscription(account) do
      %{plan: plan} -> normalize_plan(plan)
      _ -> @default_plan
    end
  end

  def current_plans(accounts) when is_list(accounts) do
    account_ids =
      accounts
      |> Enum.map(& &1.id)
      |> Enum.reject(&is_nil/1)

    subscriptions_by_account_id = active_subscription_plans_by_account_id(account_ids)

    Map.new(accounts, fn account ->
      {account.id, Map.get(subscriptions_by_account_id, account.id, @default_plan)}
    end)
  end

  def retention_days(artifact_type, plan) do
    @retention_days
    |> Map.fetch!(artifact_type)
    |> Map.get(plan, Map.fetch!(@retention_days[artifact_type], @default_plan))
  end

  def cutoff(artifact_type, plan) do
    days = retention_days(artifact_type, plan)
    DateTime.add(DateTime.utc_now(), -days, :day)
  end

  defp active_subscription_plans_by_account_id([]), do: %{}

  defp active_subscription_plans_by_account_id(account_ids) do
    Subscription
    |> where([subscription], subscription.account_id in ^account_ids)
    |> where([subscription], subscription.status == "active" or subscription.status == "trialing")
    |> distinct([subscription], subscription.account_id)
    |> order_by([subscription], asc: subscription.account_id, desc: subscription.inserted_at)
    |> select([subscription], {subscription.account_id, subscription.plan})
    |> Repo.all()
    |> Map.new(fn {account_id, plan} -> {account_id, normalize_plan(plan)} end)
  end

  defp normalize_plan(plan) when plan in @known_plans, do: plan
  defp normalize_plan(_plan), do: @default_plan
end
