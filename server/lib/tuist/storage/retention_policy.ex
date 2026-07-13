defmodule Tuist.Storage.RetentionPolicy do
  @moduledoc false

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Billing.Subscription
  alias Tuist.Repo

  @default_plan :air
  @known_plans [:air, :open_source, :pro, :enterprise]
  @maximum_hosted_retention_days 30

  @retention_days %{
    cache_artifact: %{air: 14, open_source: 14, pro: 30, enterprise: 30},
    xcode_cache_artifact: %{air: 14, open_source: 14, pro: 30, enterprise: 30},
    preview_app_build: %{air: 30, open_source: 30, pro: 30, enterprise: 30},
    preview_icon: %{air: 30, open_source: 30, pro: 30, enterprise: 30},
    build_archive: %{air: 30, open_source: 30, pro: 30, enterprise: 30},
    run_session: %{air: 30, open_source: 30, pro: 30, enterprise: 30},
    test_attachment: %{air: 30, open_source: 30, pro: 30, enterprise: 30},
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

  def retention_days(artifact_type, plan, override_days \\ nil)

  def retention_days(_artifact_type, _plan, override_days) when is_integer(override_days) and override_days > 0 do
    override_days
  end

  def retention_days(artifact_type, plan, nil) do
    retention_by_plan = Map.fetch!(@retention_days, artifact_type)

    retention_by_plan
    |> Map.get(plan, Map.fetch!(retention_by_plan, @default_plan))
    |> min(@maximum_hosted_retention_days)
  end

  def retention_days(_artifact_type, _plan, override_days) do
    raise ArgumentError, "retention days must be a positive integer, got: #{inspect(override_days)}"
  end

  def cutoff(artifact_type, plan, override_days \\ nil) do
    days = retention_days(artifact_type, plan, override_days)
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
