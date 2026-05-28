defmodule Tuist.Storage.RetentionPolicy do
  @moduledoc false

  alias Tuist.Accounts.Account
  alias Tuist.Billing

  @default_plan :air

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
      %{plan: plan} when plan in [:air, :open_source, :pro, :enterprise] -> plan
      _ -> @default_plan
    end
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
end
