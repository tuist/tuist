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

  # Lines read from ClickHouse per batch. Bounds peak memory for the
  # in-flight chunk being deflated.
  @batch_size 2_000

  # S3 multipart minimum chunk size. ExAws streams the temp file in
  # parts of this size, so the upload's peak memory is one chunk.
  @upload_chunk_bytes 5 * 1024 * 1024

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"workflow_job_id" => workflow_job_id, "account_id" => account_id}}) do
    case Accounts.get_account_by_id(account_id) do
      {:ok, account} -> archive(workflow_job_id, account)
      # Account deleted between finalize and archive — nothing to do.
      {:error, :not_found} -> :ok
    end
  end

  # Stream-gzip the job's log to a temp file and upload it via S3
  # multipart. A noisy 4-hour build can emit hundreds of MB; the old
  # in-memory `:zlib.gzip(IO.iodata_to_binary(...))` held the full
  # plain-text *and* the gzip simultaneously and reran both on every
  # Oban retry, which would OOM the worker process. With this layout
  # the peak resident set is one CH batch (~300 KB of lines) plus
  # zlib's deflate state plus the 5 MiB multipart chunk in flight.
  defp archive(workflow_job_id, account) do
    path = Briefly.create!()
    file = File.open!(path, [:write, :binary, :raw])
    z = :zlib.open()
    # `15 + 16` for windowBits selects gzip framing (header + trailer)
    # so the produced bytes are a valid `.log.gz` rather than a raw
    # deflate stream.
    :ok = :zlib.deflateInit(z, :default, :deflated, 15 + 16, 8, :default)

    line_count =
      try do
        count = stream_into_deflate(z, file, workflow_job_id)
        :ok = IO.binwrite(file, :zlib.deflate(z, "", :finish))
        count
      after
        :zlib.deflateEnd(z)
        :zlib.close(z)
        File.close(file)
      end

    if line_count == 0 do
      # The job's stream closed without ever emitting a line (a runner
      # that died before its first output, say). The gzip would still
      # contain a header + trailer; there's nothing worth serving from
      # an archive, and the chunked CH fallback handles the empty case.
      :ok
    else
      key = archive_key(account.id, workflow_job_id)

      path
      |> File.stream!(@upload_chunk_bytes)
      |> Storage.upload(key, account)

      Jobs.set_log_archived_at(workflow_job_id, DateTime.utc_now())
      :ok
    end
  end

  defp stream_into_deflate(z, file, workflow_job_id) do
    JobLogs.reduce(workflow_job_id, @batch_size, 0, fn lines, count ->
      :ok = IO.binwrite(file, :zlib.deflate(z, JobLogs.encode_lines(lines)))
      count + length(lines)
    end)
  end

  @doc """
  S3 object key for a job's gzipped log archive. Account-scoped so a
  custom-storage account's logs land in its own bucket layout.
  """
  def archive_key(account_id, workflow_job_id) when is_integer(account_id) and is_integer(workflow_job_id) do
    "runners/#{account_id}/#{workflow_job_id}/runner.log.gz"
  end
end
