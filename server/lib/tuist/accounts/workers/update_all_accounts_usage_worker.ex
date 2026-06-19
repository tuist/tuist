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

    %{
      page: 1,
      page_size: page_size
    }
    |> Accounts.list_accounts_with_usage_not_updated_today()
    |> map_accounts_to_workers()
    |> Enum.chunk_every(@insert_batch_size)
    |> Enum.each(&Oban.insert_all/1)

    :ok
  end

  def map_accounts_to_workers({[], _meta}) do
    []
  end

  def map_accounts_to_workers({accounts, meta}) do
    workers =
      Enum.map(accounts, fn %{id: account_id} ->
        UpdateAccountUsageWorker.new(%{account_id: account_id, updated_at: DateTime.utc_now()})
      end)

    current_page = meta.current_page

    case Flop.to_next_page(meta.flop, meta.total_pages) do
      %{page: ^current_page} ->
        workers

      next_page ->
        workers ++
          (next_page
           |> Accounts.list_accounts_with_usage_not_updated_today()
           |> map_accounts_to_workers())
    end
  end
end
