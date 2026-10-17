defmodule Tuist.Runners.Workers.PruneRetentionOverridesWorker do
  @moduledoc """
  Applies shorter account-specific retention to runner logs and machine metrics.
  The existing 90-day table TTLs remain the default and upper bound. Only accounts
  with an override receive mutations; scheduling walks accounts in bounded pages.
  Each account job reloads the policy so queued work does not retain stale days.
  """
  use Oban.Worker,
    queue: :storage_retention,
    max_attempts: 3,
    unique: [keys: [:account_id, :after_account_id], period: :infinity, states: :incomplete]

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Runners.Workers.PruneArchivedLogsWorker

  @page_size 100
  @tables ~w(runner_job_logs runner_job_machine_metrics)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id}}) do
    case Repo.get(Account, account_id) do
      %Account{runner_log_retention_days: days} when is_integer(days) ->
        cutoff = DateTime.add(DateTime.utc_now(), -days, :day)

        Enum.each(@tables, fn table ->
          IngestRepo.query!(
            "ALTER TABLE #{table} DELETE WHERE account_id = {account_id:Int64} AND inserted_at < {cutoff:DateTime64(6)} SETTINGS mutations_sync = 0",
            %{"account_id" => account_id, "cutoff" => cutoff}
          )
        end)

        %{"account_id" => account_id}
        |> PruneArchivedLogsWorker.new()
        |> Oban.insert!()

        :ok

      _ ->
        :ok
    end
  end

  def perform(%Oban.Job{args: args}) do
    after_account_id = Map.get(args, "after_account_id", 0)

    account_ids =
      Account
      |> where([a], a.id > ^after_account_id and not is_nil(a.runner_log_retention_days))
      |> order_by([a], asc: a.id)
      |> limit(@page_size)
      |> select([a], a.id)
      |> Repo.all()

    Enum.each(account_ids, fn account_id ->
      %{"account_id" => account_id} |> __MODULE__.new() |> Oban.insert!()
    end)

    if length(account_ids) == @page_size do
      %{"after_account_id" => List.last(account_ids)} |> __MODULE__.new() |> Oban.insert!()
    end

    :ok
  end
end
