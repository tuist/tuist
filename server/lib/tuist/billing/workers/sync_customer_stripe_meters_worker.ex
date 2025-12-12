defmodule Tuist.Billing.Workers.SyncCustomerStripeMetersWorker do
  @moduledoc """
  A daily job that updates a customer's billing meters in Stripe with yesterday's usage metrics.
  """
  use Oban.Worker

  import Tuist.Environment, only: [run_if_error_tracking_enabled: 1]

  alias Tuist.Accounts
  alias Tuist.Billing

  @impl Oban.Worker

  def perform(%Oban.Job{args: %{"customer_id" => customer_id}}) do
    date = Timex.format!(Tuist.Time.utc_now(), "{YYYY}.{0M}.{D}")
    idempotency_key = "#{customer_id}-#{date}"

    run_if_error_tracking_enabled do
      Appsignal.Span.set_sample_data(
        Appsignal.Tracer.root_span(),
        "tags",
        %{
          customer_id: customer_id,
          date: date
        }
      )
    end

    {:ok, account} = Accounts.get_account_from_customer_id(customer_id)

    {:ok, _} = Billing.update_remote_cache_hit_meter(customer_id, idempotency_key)

    if FunWithFlags.enabled?(:qa_billing_enabled, for: account) do
      {:ok, _} = Billing.update_llm_token_meters(customer_id, idempotency_key)
      {:ok, _} = Billing.update_namespace_usage_meter(customer_id, idempotency_key)
    end

    :ok
  end
end
