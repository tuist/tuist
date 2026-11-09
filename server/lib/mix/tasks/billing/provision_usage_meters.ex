defmodule Mix.Tasks.Billing.ProvisionUsageMeters do
  @shortdoc "Provisions the Stripe Meters and Prices for usage-based pricing"

  @moduledoc ~S"""
  Creates the Stripe Meters and Prices usage-based pricing bills on, and
  prints the `stripe.prices.usage_meters` map and the cache volume storage
  entry of `stripe.prices.runners` to configure with them.

      mix billing.provision_usage_meters
      mix billing.provision_usage_meters --live

  The run is idempotent, so it can be repeated after a partial failure. Live
  mode has to be asked for: the Prices it creates are what customers are
  charged on, and the environment's key decides which mode is reached.
  """
  use Mix.Task
  use Boundary, classify_to: Tuist.MixTasks

  alias Tuist.Billing.UsageMeterProvisioning
  alias Tuist.Runners.CacheVolumeBilling

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, strict: [live: :boolean])

    case UsageMeterProvisioning.provision(live: Keyword.get(opts, :live, false)) do
      {:ok, price_ids} ->
        {runners, usage_meters} = Map.split(price_ids, [CacheVolumeBilling.meter_event_name()])

        Mix.shell().info("Provisioned in #{mode()} mode:\n")
        print_section("usage_meters", usage_meters)
        print_section("runners", runners)

      {:error, :refusing_live_mode_without_opt_in} ->
        Mix.raise("The configured key addresses live mode. Pass --live to provision there.")

      {:error, :stripe_api_key_not_configured} ->
        Mix.raise("No Stripe key is configured for this environment.")

      {:error, {event_name, reason}} ->
        Mix.raise("Provisioning #{event_name} failed: #{inspect(reason)}")
    end
  end

  defp print_section(name, price_ids) do
    Mix.shell().info("#{name}:")

    Enum.each(price_ids, fn {event_name, price_id} ->
      Mix.shell().info(~s(  #{event_name}: "#{price_id}"))
    end)
  end

  defp mode do
    if UsageMeterProvisioning.test_mode?(), do: "test", else: "live"
  end
end
