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

  @impl Oban.Worker

  def perform(%Oban.Job{args: %{"customer_id" => customer_id}}) do
    date = Timex.format!(Tuist.Time.utc_now(), "{YYYY}.{0M}.{D}")
    idempotency_key = "#{customer_id}-#{date}"

    {:ok, account} = Accounts.get_account_from_customer_id(customer_id)

    meters = ["remote_cache_hit", "cache_egress"]

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
        idempotency_key: idempotency_key
      })
    )
    |> Oban.insert_all()

    :ok
  end
end
