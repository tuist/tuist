defmodule Tuist.Runners.Workers.ArchiveLogsWorker do
  @moduledoc """
  Builds a job's downloadable log archive once its stream closes.

  ## Why

  The live Logs view reads `runner_job_logs` directly — that table is
  the source of truth for tailing, per-step slicing, and search. But
  serving a "Download logs" click by re-streaming the whole job out of
  ClickHouse (chunked, line by line) scales poorly: every download
  re-scans the job's partition. GitHub sidesteps this by storing the
  finished log as a single object and handing the browser a URL to it.

  This worker does the same. When the shipper closes a job's stream
  (`done: true`), the ingest endpoint enqueues this job; it folds the
  full log into the plain-text download format, gzips it, uploads it to
  S3, and records the object key on the `runner_jobs` row. The download
  endpoint then redirects to a presigned URL instead of streaming
  ClickHouse — and falls back to the chunked stream for the window
  before the archive lands.

  ## Idempotency

  Keyed on `workflow_job_id` over a five-minute window so a redelivered
  finalize doesn't rebuild an archive that's already uploading. A
  rebuild is harmless anyway — the object key is deterministic, so a
  retry overwrites the same key.
  """
  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 3,
    unique: [period: 300, keys: [:workflow_job_id]]

  alias Tuist.Accounts
  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.Jobs
  alias Tuist.Storage

  require Logger

  @batch_size 2_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"workflow_job_id" => workflow_job_id, "account_id" => account_id}}) do
    case Accounts.get_account_by_id(account_id) do
      {:ok, account} -> archive(workflow_job_id, account)
      # Account deleted between finalize and archive — nothing to do.
      {:error, :not_found} -> :ok
    end
  end

  defp archive(workflow_job_id, account) do
    log =
      workflow_job_id
      |> JobLogs.reduce(@batch_size, [], fn lines, acc -> [acc | JobLogs.encode_lines(lines)] end)
      |> IO.iodata_to_binary()

    if log == "" do
      # Finalize fired with no captured lines — nothing worth archiving.
      :ok
    else
      key = archive_key(account.id, workflow_job_id)
      Storage.put_object(key, :zlib.gzip(log), account)
      Jobs.set_log_archive_key(workflow_job_id, key)
      :ok
    end
  end

  @doc """
  S3 object key for a job's gzipped log archive. Account-scoped so a
  custom-storage account's logs land in its own bucket layout.
  """
  def archive_key(account_id, workflow_job_id) when is_integer(account_id) and is_integer(workflow_job_id) do
    "runners/#{account_id}/#{workflow_job_id}/runner.log.gz"
  end
end
