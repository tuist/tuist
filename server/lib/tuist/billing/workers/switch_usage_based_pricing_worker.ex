defmodule Tuist.Billing.Workers.SwitchUsageBasedPricingWorker do
  @moduledoc """
  Moves Pro subscriptions onto the usage-based meters as they renew.

  Dormant until `:usage_based_pricing_switch` is enabled, for an account or
  for everyone. That flag is what paces the migration: it goes on once the
  accounts it covers have had their notice, and until then this runs daily
  and switches nobody. It is also off in any environment whose meter Prices
  are still reporting-only, because a switched subscription would carry
  nothing to bill.

  Each account is switched in the two days after its period rolls over, so
  the usage Price it carried was invoiced by that renewal and the meters
  start the new period at zero. The switch itself is idempotent, so seeing a
  subscription twice inside that window changes nothing the second time.
  """
  use Oban.Worker, max_attempts: 3

  alias Tuist.Billing
  alias Tuist.FeatureFlags

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    if Billing.usage_meter_price_ids() == [] do
      :ok
    else
      DateTime.utc_now()
      |> Billing.accounts_due_for_usage_based_pricing_switch()
      |> Enum.filter(&FeatureFlags.usage_based_pricing_switch_enabled?/1)
      |> Enum.map(&switch/1)
      |> report()
    end
  end

  defp switch(account) do
    case Billing.switch_to_usage_based_pricing(account) do
      {:ok, outcome} ->
        Logger.info("Switched account #{account.id} to usage-based pricing: #{outcome}")
        :ok

      {:error, reason} ->
        {:error, {account.id, reason}}
    end
  end

  # One account's failure is reported rather than swallowed, and a retry
  # simply switches whatever is still on the old Price.
  defp report(results) do
    case Enum.filter(results, &match?({:error, _}, &1)) do
      [] -> :ok
      failures -> {:error, "Switching to usage-based pricing failed: #{inspect(failures)}"}
    end
  end
end
