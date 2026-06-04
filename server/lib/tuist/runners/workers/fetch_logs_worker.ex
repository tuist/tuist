defmodule Tuist.Runners.Workers.FetchLogsWorker do
  @moduledoc """
  Fetches the full job log from GitHub via its Actions Logs API once a
  workflow_job completes, ingests the lines into `runner_job_logs`,
  and enqueues `ArchiveLogsWorker` to gzip + upload the archive.

  ## Why GitHub's API, not in-VM capture

  Step output from a runner job never appears in the actions/runner
  Listener's stdout or in `_diag/Worker_<utc>.log`. The .NET Worker
  spawns the user's shell with anonymous pipes and forwards each
  line directly to GitHub's `ResultsLog` HTTP stream — there's no
  stable in-VM read point short of modifying the runner binary or
  inserting a per-step shell shim. GitHub's Logs API is the
  canonical post-completion view.

  ## Streaming

  The Logs API can return arbitrarily large payloads (GitHub's
  documented cap is 4 GB per job). The worker streams the response
  via `Req`'s `:into` callback: each TCP chunk is parsed into
  whatever complete lines it carries, accumulated into a small
  in-memory batch, and flushed to ClickHouse every
  `@batch_lines` rows. Peak memory per worker stays at one
  batch + one chunk's worth of bytes regardless of total log size.

  ## Idempotency

  Keyed on `workflow_job_id` over a five-minute window so a
  redelivered `workflow_job: completed` doesn't double-ingest. Lines
  are also keyed by `(workflow_job_id, line_number)` in the
  ReplacingMergeTree, so even a duplicate run collapses on merge.
  Mid-stream failures (a chunk parses but a later one errors) leave
  partial rows in CH; Oban retries the whole job, the next pass
  re-ingests from line 1 with a newer `inserted_at`, and the RMT
  version semantics pick the latest.

  ## Retries

  GitHub returns 404 for ~30 s after the job completes while it
  finalises the log archive. We let Oban retry with backoff up to
  5 attempts before giving up.
  """
  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 5,
    unique: [period: 300, keys: [:workflow_job_id]]

  alias Tuist.GitHub.App
  alias Tuist.GitHub.Retry
  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.Workers.ArchiveLogsWorker
  alias Tuist.VCS

  require Logger

  # Lines per ClickHouse insert. Sized so the in-memory accumulator
  # stays bounded (~hundreds of KB for typical messages) while
  # amortising the per-INSERT overhead across enough rows to keep
  # the worker CPU-bound rather than network-bound.
  @batch_lines 1_000

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "workflow_job_id" => workflow_job_id,
          "account_id" => account_id,
          "installation_id" => installation_id,
          "repository" => repository
        }
      }) do
    with {:ok, installation} <- fetch_installation(installation_id),
         api_url = VCS.installation_api_url(installation),
         {:ok, %{token: token}} <- App.get_installation_token(installation, api_url: api_url),
         {:ok, line_count} <- stream_log(api_url, repository, workflow_job_id, account_id, token) do
      enqueue_archive(workflow_job_id, account_id, line_count)
      :ok
    else
      {:error, :installation_not_found} ->
        # Installation was uninstalled between the completion webhook and
        # this fetch — nothing more we can do.
        Logger.warning("runners: fetch-logs gave up; installation gone",
          workflow_job_id: workflow_job_id,
          installation_id: installation_id
        )

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_installation(installation_id) do
    case VCS.get_github_app_installation_by_installation_id(to_string(installation_id)) do
      {:ok, installation} -> {:ok, installation}
      _ -> {:error, :installation_not_found}
    end
  end

  defp stream_log(api_url, repository, workflow_job_id, account_id, token) do
    url = "#{api_url}/repos/#{repository}/actions/jobs/#{workflow_job_id}/logs"
    initial = new_stream_state(workflow_job_id, account_id)

    req_opts =
      [
        url: url,
        headers: [
          {"Authorization", "Bearer #{token}"},
          {"Accept", "application/vnd.github+json"},
          {"X-GitHub-Api-Version", "2022-11-28"}
        ],
        # Follow the 302 to the actual log payload (S3/Azure).
        redirect: true,
        # Logs come back as plain text, not JSON.
        decode_body: false,
        into: fn {:data, chunk}, {req, resp} ->
          state = Req.Response.get_private(resp, :log_stream, initial)
          state = consume_chunk(state, chunk)
          {:cont, {req, Req.Response.put_private(resp, :log_stream, state)}}
        end
      ] ++ Retry.retry_options()

    case Req.get(req_opts) do
      {:ok, %{status: 200} = resp} ->
        state =
          resp
          |> Req.Response.get_private(:log_stream, initial)
          |> consume_remainder()
          |> flush_batch()

        {:ok, state.line_number}

      # 404 happens for ~30 s after completion while GitHub finalises
      # the log archive. Oban's exponential backoff covers this.
      {:ok, %{status: 404}} ->
        {:error, :log_not_ready_yet}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp new_stream_state(workflow_job_id, account_id) do
    %{
      workflow_job_id: workflow_job_id,
      account_id: account_id,
      partial: "",
      batch: [],
      batch_count: 0,
      line_number: 0,
      last_ts: DateTime.utc_now(),
      bom_stripped: false
    }
  end

  # Appends a chunk's complete lines to the in-memory batch, flushing
  # to CH if the batch crosses `@batch_lines`. The trailing fragment
  # (the part after the chunk's last `\n`) is stashed on `:partial`
  # to be merged with the next chunk.
  defp consume_chunk(state, chunk) do
    {rows, state} = parse_chunk(chunk, state)

    state = %{
      state
      | batch: state.batch ++ rows,
        batch_count: state.batch_count + length(rows)
    }

    if state.batch_count >= @batch_lines, do: flush_batch(state), else: state
  end

  # End-of-stream: parse whatever's left in `:partial` as one final
  # line (GitHub's payload ends with a trailing `\n`, but be tolerant
  # in case it doesn't).
  defp consume_remainder(%{partial: ""} = state), do: state

  defp consume_remainder(state) do
    {row, state} = take_line(state.partial, %{state | partial: ""})

    case row do
      nil -> state
      _ -> %{state | batch: state.batch ++ [row], batch_count: state.batch_count + 1}
    end
  end

  defp flush_batch(%{batch: []} = state), do: state

  defp flush_batch(%{batch: batch} = state) do
    :ok = JobLogs.append(batch)
    %{state | batch: [], batch_count: 0}
  end

  defp parse_chunk(chunk, state) do
    chunk = if state.bom_stripped, do: chunk, else: String.trim_leading(chunk, "﻿")
    combined = state.partial <> chunk
    parts = String.split(combined, "\n")
    {full_lines, [remainder]} = Enum.split(parts, -1)

    {rows, state} =
      Enum.reduce(full_lines, {[], state}, fn line, {acc, st} ->
        case take_line(line, st) do
          {nil, st} -> {acc, st}
          {row, st} -> {[row | acc], st}
        end
      end)

    {Enum.reverse(rows), %{state | partial: remainder, bom_stripped: true}}
  end

  defp take_line("", state), do: {nil, state}

  defp take_line(line, state) do
    line_number = state.line_number + 1
    {ts, msg} = parse_ts_line(line, state.last_ts)

    row = %{
      workflow_job_id: state.workflow_job_id,
      account_id: state.account_id,
      line_number: line_number,
      ts: ts,
      message: msg
    }

    {row, %{state | line_number: line_number, last_ts: ts}}
  end

  @doc """
  Parses a GitHub Actions Logs-API payload (plain text, ISO-stamped
  per line) into the row shape `JobLogs.append/1` consumes.

  Synchronous variant exposed for the dev seed, which feeds a small
  on-disk fixture through the same parser the production streaming
  worker uses.

  ## Format

      2026-06-02T15:31:03.1234567Z ##[group]Run echo "Hostname: $(hostname)"
      2026-06-02T15:31:03.1234567Z Hostname: tuist-tuist-runner-pool-...

  Lines without a parseable timestamp keep the full text as
  `message` and carry the previous line's `ts` forward (or `now/0`
  for the first line) so per-step slicing stays monotonic.
  """
  def parse_lines(text, workflow_job_id, account_id) do
    state = new_stream_state(workflow_job_id, account_id)
    {rows, state} = parse_chunk(text, state)
    state = consume_remainder(%{state | batch: state.batch ++ rows})
    state.batch
  end

  defp parse_ts_line(line, last_ts) do
    case String.split(line, " ", parts: 2) do
      [ts_str, msg] ->
        case DateTime.from_iso8601(ts_str) do
          {:ok, ts, _offset} -> {with_usec_precision(ts), msg}
          _ -> {last_ts, line}
        end

      [bare] ->
        {last_ts, bare}
    end
  end

  # `DateTime64(6)` on the ClickHouse column requires 6-digit µs
  # precision. GitHub stamps with 7 digits (.NET DateTime.UtcNow);
  # `DateTime.from_iso8601/1` preserves the raw value but advertises
  # `6` only when six digits were given, so we normalise.
  defp with_usec_precision(%DateTime{microsecond: {value, _precision}} = dt) do
    %{dt | microsecond: {value, 6}}
  end

  defp enqueue_archive(_workflow_job_id, _account_id, 0), do: :ok

  defp enqueue_archive(workflow_job_id, account_id, _line_count) do
    %{workflow_job_id: workflow_job_id, account_id: account_id}
    |> ArchiveLogsWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning("runners: failed to enqueue log archive: #{inspect(reason)}",
          workflow_job_id: workflow_job_id
        )

        :ok
    end
  end
end
