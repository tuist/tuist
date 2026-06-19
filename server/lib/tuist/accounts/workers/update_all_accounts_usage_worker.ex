defmodule Tuist.Accounts.Workers.UpdateAllAccountsUsageWorker do
  @moduledoc ~S"""
  The account usage might be expensive to calculate, so we calculate it in a worker that runs periodically.
  """
  use Oban.Worker

  alias Tuist.Accounts
  alias Tuist.Accounts.Workers.UpdateAccountUsageWorker

  @page_size 100

  # PostgreSQL's wire protocol caps a single statement at 65535 bind parameters.
  # Oban binds 9 columns per job, so we insert in batches well under that ceiling
  # to avoid `Postgrex.QueryError` when the backlog of accounts is large.
  @insert_batch_size 1_000

  @impl Oban.Worker
  def perform(%{args: args}) do
    page_size = Map.get(args, "page_size", @page_size)
    now = DateTime.utc_now()

    # We read every stale account id up front (a stable, side-effect-free
    # snapshot) before enqueuing anything. Streaming inserts per page would
    # let the async per-account workers flip accounts out of the
    # `not_updated_today` filter mid-run and shift the offset pagination,
    # skipping accounts. Collecting ids keeps peak memory to the id list
    # plus a single batch of changesets, which are built on demand per chunk.
    %{
      page: 1,
      page_size: page_size
    }
    |> Accounts.list_accounts_with_usage_not_updated_today()
    |> stale_account_ids()
    |> Enum.chunk_every(@insert_batch_size)
    |> Enum.each(&insert_usage_workers(&1, now))

    :ok
  end

  def stale_account_ids({[], _meta}) do
    []
  end

  def stale_account_ids({accounts, meta}) do
    ids = Enum.map(accounts, & &1.id)
    current_page = meta.current_page

    case Flop.to_next_page(meta.flop, meta.total_pages) do
      %{page: ^current_page} ->
        ids

      next_page ->
        ids ++
          (next_page
           |> Accounts.list_accounts_with_usage_not_updated_today()
           |> stale_account_ids())
    end
  end

  defp insert_usage_workers(account_ids, now) do
    account_ids
    |> Enum.map(&UpdateAccountUsageWorker.new(%{account_id: &1, updated_at: now}))
    |> Oban.insert_all()
  end
end
