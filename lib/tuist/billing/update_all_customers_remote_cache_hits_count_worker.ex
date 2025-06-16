defmodule Tuist.Billing.UpdateAllCustomersRemoteCacheHitsCountWorker do
  @moduledoc """
  A job that gets pairs of customer id and remote cache hits count, and schedules jobs to push the measurement to Stripe.
  """
  use Oban.Worker, max_attempts: 1

  alias Tuist.Accounts
  alias Tuist.Billing.UpdateCustomerRemoteCacheHitsCountWorker

  @page_size 100

  @impl Oban.Worker
  def perform(%{args: args}) do
    page_size = Map.get(args, "page_size", @page_size)

    %{
      page: 1,
      page_size: page_size
    }
    |> Accounts.list_customer_id_and_remote_cache_hits_count_pairs()
    |> accounts_to_workers()
    |> Oban.insert_all()
  end

  def accounts_to_workers({[], _meta}) do
    []
  end

  def accounts_to_workers({customer_id_and_remote_cache_hits_count_pairs, meta}) do
    workers =
      Enum.map(customer_id_and_remote_cache_hits_count_pairs, fn {customer_id, remote_cache_hits_count} ->
        UpdateCustomerRemoteCacheHitsCountWorker.new(%{
          customer_id: customer_id,
          remote_cache_hits_count: remote_cache_hits_count
        })
      end)

    current_page = meta.current_page

    case Flop.to_next_page(meta.flop, meta.total_pages) do
      %{page: ^current_page} ->
        workers

      next_page ->
        workers ++
          (next_page
           |> Accounts.list_customer_id_and_remote_cache_hits_count_pairs()
           |> accounts_to_workers())
    end
  end
end
