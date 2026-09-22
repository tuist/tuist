defmodule Tuist.Billing.Workers.SwitchUsageBasedPricingWorker do
  @moduledoc """
  Moves Pro subscriptions onto the usage-based meters.

  `:usage_based_pricing_switch` decides who and when: an account is
  switched once the flag is enabled for it, or for everyone, and not
  before. That is what paces the migration, one account or one wave at a
  time, without a deploy. Enabling it for an account just after its renewal
  is what keeps the accounting whole, since the usage Price leaves without
  being settled for the period it is removed in.

  Nothing happens either while the environment's meter Prices are still
  reporting-only, because a switched subscription would carry nothing to
  bill.

  Running daily over the accounts the flag covers makes this a convergence
  loop rather than a one-off migration: a subscription that already carries
  the meters is left alone, and one that somehow lost an item gets it back
  on the next run.
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
      Billing.accounts_with_pro_subscriptions()
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
