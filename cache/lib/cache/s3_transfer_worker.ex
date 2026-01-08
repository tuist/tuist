defmodule Cache.S3TransferWorker do
  @moduledoc """
  Oban cron worker that processes batches of S3 transfers.

  Runs every minute and processes pending uploads and downloads from the
  s3_transfers queue. This replaces per-request Oban job insertion to avoid
  SQLite contention under bursty load.

  Rate-limited transfers (429 errors) are kept in the queue for retry on the
  next run. Other errors are logged and the transfer is removed.
  """

  use Oban.Worker, queue: :s3_transfers

  alias Cache.Disk
  alias Cache.S3
  alias Cache.S3Transfers

  require Logger

  @batch_size 1000
  @concurrency 20

  @impl Oban.Worker
  def perform(_job) do
    process_batch(:upload, &S3.upload/1)
    process_batch(:download, &S3.download/1)
    :ok
  end

  defp process_batch(type, operation_fn) do
    transfers = S3Transfers.pending(type, @batch_size)

    if transfers != [] do
      Logger.info("Processing #{length(transfers)} pending S3 #{type}s")

      processed_ids =
        transfers
        |> Task.async_stream(
          fn transfer ->
            result = operation_fn.(transfer.key)
            {transfer, result}
          end,
          max_concurrency: @concurrency,
          timeout: 60_000,
          on_timeout: :kill_task
        )
        |> Enum.map(&handle_result(type, &1))
        |> Enum.reject(&is_nil/1)

      S3Transfers.delete_all(processed_ids)
      Logger.info("Completed #{length(processed_ids)} S3 #{type}s")
    end
  end

  defp handle_result(_type, {:ok, {transfer, :ok}}), do: transfer.id

  defp handle_result(:download, {:ok, {transfer, {:ok, :hit}}}) do
    {:ok, %{size: size}} = transfer.key |> Disk.artifact_path() |> File.stat()

    :telemetry.execute([:cache, transfer.artifact_type, :download, :s3_hit], %{size: size}, %{
      account_handle: transfer.account_handle,
      project_handle: transfer.project_handle
    })

    transfer.id
  end

  defp handle_result(:download, {:ok, {transfer, {:ok, :miss}}}) do
    :telemetry.execute([:cache, transfer.artifact_type, :download, :s3_miss], %{}, %{
      account_handle: transfer.account_handle,
      project_handle: transfer.project_handle
    })

    transfer.id
  end

  defp handle_result(_type, {:ok, {transfer, {:ok, _}}}), do: transfer.id

  defp handle_result(type, {:ok, {_transfer, {:error, :rate_limited}}}) do
    Logger.warning("S3 #{type} rate limited, will retry on next run")
    nil
  end

  defp handle_result(type, {:ok, {transfer, {:error, reason}}}) do
    Logger.warning("S3 #{type} failed for transfer #{transfer.id}: #{inspect(reason)}")
    transfer.id
  end

  defp handle_result(type, {:exit, reason}) do
    Logger.warning("S3 #{type} task exited: #{inspect(reason)}")
    nil
  end
end
