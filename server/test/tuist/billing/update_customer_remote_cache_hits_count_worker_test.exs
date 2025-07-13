defmodule Tuist.Billing.UpdateCustomerRemoteCacheHitsCountWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Billing.UpdateCustomerRemoteCacheHitsCountWorker

  test "updates the remote cache hit for the given customer_id and remote cache hits count" do
    # Given
    customer_id = UUIDv7.generate()
    remote_cache_hits_count = 2

    expect(Tuist.Billing, :update_remote_cache_hit_meter, fn {^customer_id, ^remote_cache_hits_count} ->
      :ok
    end)

    # When/Then
    UpdateCustomerRemoteCacheHitsCountWorker.perform(%Oban.Job{
      args: %{
        "customer_id" => customer_id,
        "remote_cache_hits_count" => remote_cache_hits_count
      }
    })
  end
end
