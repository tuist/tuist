defmodule SwiftRegistry.S3TransferWorker do
  @moduledoc """
  Oban cron worker that processes pending registry S3 uploads and downloads.
  """

  use Oban.Worker, queue: :s3_transfers

  alias SwiftRegistry.Disk
  alias SwiftRegistry.S3
  alias SwiftRegistry.S3Transfers

  require Logger

  @batch_size 7500
  @concurrency 50

  @impl Oban.Worker
  def perform(_job) do
    process_batch(:upload)
    process_batch(:download)
    :ok
  end

  defp process_batch(type) do
    transfers = S3Transfers.pending(type, @batch_size)

    if transfers != [] do
      Logger.info("Processing #{length(transfers)} pending S3 #{type}s")

      processed_ids =
        transfers
        |> Task.async_stream(
          fn transfer ->
            result = execute_transfer(type, transfer)
            {transfer, result}
          end,
          max_concurrency: @concurrency,
          timeout: to_timeout(minute: 5),
          on_timeout: :kill_task
        )
        |> Enum.map(&handle_result(type, &1))
        |> Enum.reject(&is_nil/1)

      S3Transfers.delete_all(processed_ids)
      Logger.info("Completed #{length(processed_ids)} S3 #{type}s")
    end
  end

  defp execute_transfer(:upload, %{key: key}) do
    local_path = Disk.artifact_path(key)

    if File.exists?(local_path) do
      S3.upload_file(key, local_path, type: :registry)
    else
      :ok
    end
  end

  defp execute_transfer(:download, %{key: key}) do
    S3.download(key, type: :registry)
  end

  defp handle_result(_type, {:ok, {transfer, :ok}}), do: transfer.id

  defp handle_result(:download, {:ok, {transfer, {:ok, :hit}}}) do
    size =
      case transfer.key |> Disk.artifact_path() |> File.stat() do
        {:ok, %{size: size}} -> size
        {:error, _} -> 0
      end

    :telemetry.execute([:swift_registry, :registry, :download, :s3_hit], %{size: size}, %{
      account_handle: transfer.account_handle,
      project_handle: transfer.project_handle
    })

    transfer.id
  end

  defp handle_result(:download, {:ok, {transfer, {:ok, :miss}}}) do
    :telemetry.execute([:swift_registry, :registry, :download, :s3_miss], %{}, %{
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
    Logger.warning("S3 #{type} failed for transfer #{transfer.id}: #{inspect(reason)}; will retry on next run")
    nil
  end

  defp handle_result(type, {:exit, reason}) do
    Logger.warning("S3 #{type} task exited: #{inspect(reason)}")
    nil
  end
end
