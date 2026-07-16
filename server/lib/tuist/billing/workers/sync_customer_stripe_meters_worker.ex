defmodule Tuist.Billing.Workers.SyncCustomerStripeMetersWorker do
  @moduledoc """
  A daily job that fans out one `SyncCustomerStripeMeterWorker` per Stripe meter
  for a customer. Splitting the meters into independent jobs isolates their
  retries: a single meter that fails or is not yet provisioned in Stripe retries
  and surfaces on its own without crashing the job or blocking the other meters.
  """
  use Oban.Worker

  alias Tuist.Accounts
  alias Tuist.Billing.Workers.SyncCustomerStripeMeterWorker
  alias Tuist.FeatureFlags

  @impl Oban.Worker

  def perform(%Oban.Job{args: %{"customer_id" => customer_id, "usage_date" => usage_date}}) do
    {:ok, account} = Accounts.get_account_from_customer_id(customer_id)

    meters = ["remote_cache_hit"]

    meters =
      if FeatureFlags.kura_billing_enabled?(account) do
        meters ++ ["cache_egress"]
      else
        meters
      end

    meters =
      if FunWithFlags.enabled?(:qa_billing_enabled, for: account) do
        meters ++ ["llm_token"]
      else
        meters
      end

    meters
    |> Enum.map(
      &SyncCustomerStripeMeterWorker.new(%{
        customer_id: customer_id,
        meter: &1,
        usage_date: usage_date,
        idempotency_key: "#{customer_id}-#{usage_date}"
      })
    )
    |> Oban.insert_all()

    :ok
  end
end
