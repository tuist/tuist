defmodule Tuist.Billing.Workers.SyncCustomerStripeMeterWorker do
  @moduledoc """
  Updates a single Stripe billing meter for a customer with yesterday's usage.

  Spawned by `SyncCustomerStripeMetersWorker`, one job per meter, so each meter
  reports independently: a failing Stripe call retries on its own and surfaces
  through Oban without affecting the other meters.
  """
  use Oban.Worker

  alias Tuist.Accounts
  alias Tuist.Billing

  @impl Oban.Worker

  def perform(%Oban.Job{
        args: %{
          "customer_id" => customer_id,
          "meter" => meter,
          "usage_date" => usage_date,
          "idempotency_key" => idempotency_key
        }
      }) do
    if Tuist.Environment.error_tracking_enabled?() do
      Sentry.Context.set_extra_context(%{customer_id: customer_id, meter: meter, usage_date: usage_date})
    end

    with {:ok, _} <- update_meter(meter, customer_id, idempotency_key, Date.from_iso8601!(usage_date)) do
      :ok
    end
  end

  defp update_meter("remote_cache_hit", customer_id, idempotency_key, usage_date) do
    Billing.update_remote_cache_hit_meter(customer_id, idempotency_key, usage_date)
  end

  defp update_meter("cache_egress", customer_id, idempotency_key, usage_date) do
    {:ok, account} = Accounts.get_account_from_customer_id(customer_id)
    Billing.update_cache_egress_meter(account, idempotency_key, usage_date)
  end

  defp update_meter("llm_token", customer_id, idempotency_key, usage_date) do
    Billing.update_llm_token_meters(customer_id, idempotency_key, usage_date)
  end
end
