defmodule TuistWeb.RunnerJobReportsController do
  @moduledoc """
  Receives masked logs and outcomes from Buildkite and GitLab jobs.

  Every request authenticates with a token scoped to one existing job and
  account. The job container never receives the fleet's ServiceAccount
  credential or a reusable provider runner credential. Billing timestamps
  are observed on the server, and log ingestion is bounded by bytes,
  line count and a short grace period after completion.
  """

  use TuistWeb, :controller

  alias Tuist.Runners.Buildkite
  alias Tuist.Runners.Buildkite.LogParser
  alias Tuist.Runners.GitLab
  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.JobReports
  alias Tuist.Runners.JobReportToken, as: ReportToken

  require Logger

  @max_log_bytes 64 * 1024 * 1024

  # The byte cap bounds one request; this bounds the job. Line numbers are
  # the ReplacingMergeTree key, so refusing everything past the ceiling
  # caps what a job can store however many times it posts.
  @max_log_lines 1_000_000

  # A job's log is uploaded after its finish report, so logs are still
  # accepted for a while past completion. Past that the token can no
  # longer add to a settled job.
  @log_grace_seconds 900

  @doc """
  `POST /api/internal/runners/jobs/logs`

      { "lines": ["...", "..."], "first_line_number": 1 }

  Lines are appended in the order given. The ReplacingMergeTree key
  `(workflow_job_id, line_number)` collapses a re-posted batch, so the
  hook may retry freely.
  """
  def logs(conn, params) do
    first_line_number = params |> Map.get("first_line_number", 1) |> to_integer(1)

    with {:ok, %{workflow_job_id: workflow_job_id, account_id: account_id} = identity} <- authenticate(conn),
         :ok <- accepting_logs(workflow_job_id),
         {:ok, lines} <- parse_lines(params),
         :ok <- within_line_ceiling(first_line_number, lines) do
      parser = if identity[:provider] == :gitlab, do: GitLab.LogParser, else: LogParser

      lines
      |> parser.parse(first_line_number, DateTime.utc_now())
      |> Enum.map(&Map.merge(&1, %{workflow_job_id: workflow_job_id, account_id: account_id}))
      |> JobLogs.append()

      send_resp(conn, :no_content, "")
    else
      error -> render_error(conn, error, "runner log ingest")
    end
  end

  @doc """
  `POST /api/internal/runners/jobs/finish`

      {
        "exit_status": 0,
        "cancelled": false,
        "started_at": 1750684800,
        "finished_at": 1750684860
      }

  Closes the lifecycle row, frees the account's concurrency slot and
  records the billable window. A failed write is reported as 500 rather
  than swallowed: the window is recorded nowhere else, and the hook
  retries on a non-2xx.
  """
  def finish(conn, params) do
    with {:ok, %{workflow_job_id: workflow_job_id, account_id: account_id}} <- authenticate(conn),
         {:ok, runner_name} <- JobReports.runner_name_for_job(workflow_job_id, account_id) do
      # The window is measured server-side; only the outcome comes from
      # the job, which could decide it by exiting with that status anyway.
      report = %{
        workflow_job_id: workflow_job_id,
        conclusion: JobReports.conclusion_for(outcome(params))
      }

      provider = if GitLab.get_job_for_account(account_id, workflow_job_id), do: GitLab, else: Buildkite

      case provider.record_job_finished(runner_name, account_id, report) do
        :ok ->
          send_resp(conn, :no_content, "")

        {:error, reason} ->
          Logger.error("runners: finish report failed",
            workflow_job_id: workflow_job_id,
            reason: inspect(reason)
          )

          conn |> put_status(:internal_server_error) |> json(%{error: "finish report failed"})
      end
    else
      {:error, :no_session} ->
        # The job's session is already closed — a duplicate report, or one
        # that arrived after recovery reaped the Pod. The lifecycle row is
        # settled either way, so this is not a failure the hook should
        # retry.
        send_resp(conn, :no_content, "")

      error ->
        render_error(conn, error, "runner finish report")
    end
  end

  # A settled job stops accepting log lines once the upload that follows
  # its finish report has had time to land.
  defp accepting_logs(workflow_job_id) do
    if JobReports.log_window_open?(workflow_job_id, @log_grace_seconds) do
      :ok
    else
      {:error, :job_settled}
    end
  end

  defp within_line_ceiling(first_line_number, lines) do
    if first_line_number >= 1 and first_line_number + length(lines) - 1 <= @max_log_lines do
      :ok
    else
      {:error, {:invalid_field, "first_line_number"}}
    end
  end

  defp authenticate(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> ReportToken.verify(token)
      ["bearer " <> token] when token != "" -> ReportToken.verify(token)
      _ -> {:error, :missing_bearer}
    end
  end

  defp outcome(params) do
    %{
      exit_status: params |> Map.get("exit_status", 1) |> to_integer(1),
      cancelled: Map.get(params, "cancelled") == true
    }
  end

  defp parse_lines(%{"lines" => lines}) when is_list(lines) do
    if Enum.all?(lines, &is_binary/1) and byte_size_of(lines) <= @max_log_bytes do
      {:ok, lines}
    else
      {:error, {:invalid_field, "lines"}}
    end
  end

  defp parse_lines(_params), do: {:error, {:invalid_field, "lines"}}

  defp byte_size_of(lines), do: Enum.reduce(lines, 0, &(byte_size(&1) + &2))

  defp to_integer(value, _default) when is_integer(value), do: value

  defp to_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> default
    end
  end

  defp to_integer(_value, default), do: default

  defp render_error(conn, {:error, :missing_bearer}, _context) do
    conn |> put_status(:unauthorized) |> json(%{error: "missing bearer token"})
  end

  defp render_error(conn, {:error, :expired}, _context) do
    conn |> put_status(:unauthorized) |> json(%{error: "report token expired"})
  end

  defp render_error(conn, {:error, :invalid}, _context) do
    conn |> put_status(:unauthorized) |> json(%{error: "invalid report token"})
  end

  defp render_error(conn, {:error, {:invalid_field, field}}, _context) do
    conn |> put_status(:bad_request) |> json(%{error: "invalid #{field}"})
  end

  defp render_error(conn, {:error, :job_settled}, _context) do
    conn |> put_status(:gone) |> json(%{error: "job is no longer accepting reports"})
  end
end
