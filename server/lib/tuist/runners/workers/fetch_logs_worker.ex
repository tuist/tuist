defmodule Tuist.Runners.Workers.FetchLogsWorker do
  @moduledoc """
  Fetches the full job log from GitHub via its Actions Logs API once a
  workflow_job completes, ingests the lines into `runner_job_logs`,
  flips `log_state` to `complete`, and enqueues `ArchiveLogsWorker`
  to gzip + upload the archive.

  ## Why GitHub's API, not in-VM capture

  Step output from a runner job never appears in the actions/runner
  Listener's stdout or in `_diag/Worker_<utc>.log`. The .NET Worker
  spawns the user's shell with anonymous pipes and forwards each line
  directly to GitHub's `ResultsLog` HTTP stream — locally there's no
  stable place to read it from without modifying the runner binary or
  inserting a shell shim. GitHub's Logs API, fetched once the job
  completes, gives us the canonical post-completion view. The earlier
  in-VM capture iterations (run.sh stdout, Worker diag tail) only
  surfaced framework lifecycle messages; this path surfaces the
  actual step content.

  ## Idempotency

  Keyed on `workflow_job_id` over a five-minute window so a
  redelivered `workflow_job: completed` doesn't double-ingest. Lines
  are also keyed by `(workflow_job_id, line_number)` in the
  ReplacingMergeTree, so even a duplicate run collapses on merge.

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
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.ArchiveLogsWorker
  alias Tuist.VCS

  require Logger

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
         {:ok, body} <- fetch_log(api_url, repository, workflow_job_id, token) do
      lines = parse_lines(body, workflow_job_id, account_id)
      :ok = JobLogs.append(lines)
      :ok = Jobs.set_log_state(workflow_job_id, "complete", line_count: length(lines))

      enqueue_archive(workflow_job_id, account_id, length(lines))

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

  defp fetch_log(api_url, repository, workflow_job_id, token) do
    url = "#{api_url}/repos/#{repository}/actions/jobs/#{workflow_job_id}/logs"

    req_opts =
      [
        url: url,
        headers: [
          {"Authorization", "Bearer #{token}"},
          {"Accept", "application/vnd.github+json"},
          {"X-GitHub-Api-Version", "2022-11-28"}
        ],
        # Follow the 302 redirect to the actual log payload.
        redirect: true,
        # Logs come back as plain text, not JSON.
        decode_body: false
      ] ++ Retry.retry_options()

    case Req.get(req_opts) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

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

  @doc """
  Parses a GitHub Actions Logs-API response (plain text, ISO-stamped
  per line) into the row shape `JobLogs.append/1` consumes.

  Public so the dev seed can reuse the same parsing path as the
  webhook-driven worker — re-implementing it inline drifts.

  ## Format

      2026-06-02T15:31:03.1234567Z ##[group]Run echo "Hostname: $(hostname)"
      2026-06-02T15:31:03.1234567Z Hostname: tuist-tuist-runner-pool-...

  We split on lines, peel off the timestamp, and stash the rest as
  the message. Lines without a parseable timestamp keep the full
  text and stamp `ts` with the previous line's value (or now() on
  the very first line) so per-step slicing stays monotonic.
  """
  def parse_lines(text, workflow_job_id, account_id) do
    text
    |> String.split("\n", trim: false)
    |> Enum.reject(&(&1 == ""))
    |> Enum.with_index(1)
    |> Enum.map_reduce(DateTime.utc_now(), fn {line, n}, last_ts ->
      {ts, msg} = parse_ts_line(line, last_ts)

      row = %{
        workflow_job_id: workflow_job_id,
        account_id: account_id,
        line_number: n,
        ts: ts,
        message: msg
      }

      {row, ts}
    end)
    |> elem(0)
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
