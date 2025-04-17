defmodule Tuist.Billing.UpdateCustomerRemoteCacheHitsCountWorker do
  @moduledoc """
  Given a customer id and a remote cache hits count it updates the value in Stripe.
  """
  use Oban.Worker

  alias Tuist.Billing

  @impl Oban.Worker

  def perform(%Oban.Job{args: %{"customer_id" => customer_id, "remote_cache_hits_count" => remote_cache_hits_count}}) do
    Billing.update_remote_cache_hit_meter({customer_id, remote_cache_hits_count})
  end
end
