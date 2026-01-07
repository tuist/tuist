defmodule Cache.S3Transfers.PromExPlugin do
  @moduledoc """
  Prometheus metrics for S3 transfer queue monitoring.

  Exposes gauges for pending upload and download queue depths,
  polled every 15 seconds.
  """
  use PromEx.Plugin

  import Ecto.Query

  alias Cache.Repo
  alias Cache.S3Transfer

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 15_000)

    Polling.build(
      :cache_s3_transfers_polling_metrics,
      poll_rate,
      {__MODULE__, :execute_queue_metrics, []},
      [
        last_value(
          [:tuist_cache, :s3_transfers, :pending, :uploads],
          event_name: [:cache, :prom_ex, :s3_transfers, :queue],
          measurement: :pending_uploads,
          description: "Number of pending S3 uploads in the queue."
        ),
        last_value(
          [:tuist_cache, :s3_transfers, :pending, :downloads],
          event_name: [:cache, :prom_ex, :s3_transfers, :queue],
          measurement: :pending_downloads,
          description: "Number of pending S3 downloads in the queue."
        ),
        last_value(
          [:tuist_cache, :s3_transfers, :pending, :total],
          event_name: [:cache, :prom_ex, :s3_transfers, :queue],
          measurement: :total,
          description: "Total pending S3 transfers in the queue."
        )
      ]
    )
  end

  @doc false
  def execute_queue_metrics do
    pending_uploads = count_pending(:upload)
    pending_downloads = count_pending(:download)

    :telemetry.execute(
      [:cache, :prom_ex, :s3_transfers, :queue],
      %{
        pending_uploads: pending_uploads,
        pending_downloads: pending_downloads,
        total: pending_uploads + pending_downloads
      },
      %{}
    )
  end

  defp count_pending(type) do
    S3Transfer
    |> where([t], t.type == ^type)
    |> Repo.aggregate(:count, :id)
  end
end
