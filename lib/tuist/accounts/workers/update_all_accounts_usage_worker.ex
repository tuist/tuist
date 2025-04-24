defmodule Tuist.Accounts.Workers.UpdateAllAccountsUsageWorker do
  @moduledoc ~S"""
  The account usage might be expensive to calculate, so we calculate it in a worker that runs periodically.
  """
  use Oban.Worker

  alias Tuist.Accounts
  alias Tuist.Accounts.Workers.UpdateAccountUsageWorker

  @page_size 100

  @impl Oban.Worker
  def perform(%{args: args}) do
    page_size = Map.get(args, "page_size", @page_size)

    %{
      page: 1,
      page_size: page_size
    }
    |> Accounts.list_accounts_with_usage_not_updated_today()
    |> process_results()
  end

  def process_results({[], _meta}) do
    :ok
  end

  def process_results({accounts, meta}) do
    Enum.each(accounts, fn %{id: account_id} ->
      %{
        account_id: account_id
      }
      |> UpdateAccountUsageWorker.new()
      |> Oban.insert()
    end)

    current_page = meta.current_page

    case Flop.to_next_page(meta.flop, meta.total_pages) do
      %{page: ^current_page} ->
        :ok

      next_page ->
        next_page
        |> Accounts.list_accounts_with_usage_not_updated_today()
        |> process_results()
    end
  end
end
