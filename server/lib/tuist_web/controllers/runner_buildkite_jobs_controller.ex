defmodule TuistWeb.RunnerBuildkiteJobsController do
  @moduledoc """
  Ingests a Buildkite job's log and outcome from the runner that ran it.

  The GitHub lane pulls both from GitHub after the fact: logs from the
  Actions Logs API, the outcome from the `workflow_job.completed`
  webhook. Neither is available here on the same terms. Buildkite's log
  endpoint lives on the REST API, which takes an organization API token
  rather than the cluster agent token, so using it would mean asking the
  customer for a second, broader credential purely so we can read back
  output that passed through our own machine on its way out.

  So the runner reports instead. `buildkite-agent` runs with
  `--enable-job-log-tmpfile`, which writes the job's log verbatim to a
  path it exports as `BUILDKITE_JOB_LOG_TMPFILE`, and a global `pre-exit`
  hook posts that file here along with the job's window and exit status.
  This is the capture point GitHub's runner does not offer: there, step
  output goes straight from the worker to GitHub over HTTP with no stable
  in-VM read point, which is why that lane pulls.

  ## Why not the Pod's ServiceAccount token

  Both endpoints authenticate with a
  `Tuist.Runners.Buildkite.ReportToken` minted for one job at dispatch,
  not with the Pod credential the rest of the runner endpoints use. On
  the Linux fleet the job container holds no ServiceAccount token by
  design — the poller init container claims the job and hands the
  credential over on a shared volume so untrusted workflow code never
  sits beside a token that can claim more work. Reporting with that token
  would have undone the isolation, and restricting the Buildkite lane to
  macOS to avoid the question would have left half the fleet out.

  A report token authorizes only what the job it names could already do:
  write its own log, and declare its own exit status. It cannot claim
  work or reach another account, so staging it into the job container
  changes nothing about what that container can reach.

  The job the report belongs to comes from the token, never from the
  body or the path, so a job cannot write over another's history.
  """

  use TuistWeb, :controller

  alias Tuist.Runners.Buildkite
  alias Tuist.Runners.Buildkite.LogParser
  alias Tuist.Runners.Buildkite.ReportToken
  alias Tuist.Runners.JobLogs

  require Logger

  @max_log_bytes 64 * 1024 * 1024

  @doc """
  `POST /api/internal/runners/buildkite/logs`

      { "lines": ["...", "..."], "first_line_number": 1 }

  Lines are appended in the order given. The ReplacingMergeTree key
  `(workflow_job_id, line_number)` collapses a re-posted batch, so the
  hook may retry freely.
  """
  def logs(conn, params) do
    with {:ok, %{workflow_job_id: workflow_job_id, account_id: account_id}} <- authenticate(conn),
         {:ok, lines} <- parse_lines(params) do
      lines
      |> LogParser.parse(
        params |> Map.get("first_line_number", 1) |> to_integer(1),
        DateTime.utc_now()
      )
      |> Enum.map(&Map.merge(&1, %{workflow_job_id: workflow_job_id, account_id: account_id}))
      |> JobLogs.append()

      send_resp(conn, :no_content, "")
    else
      error -> render_error(conn, error, "buildkite log ingest")
    end
  end

  @doc """
  `POST /api/internal/runners/buildkite/finish`

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
         {:ok, runner_name} <- Buildkite.runner_name_for_job(workflow_job_id, account_id) do
      report = %{
        workflow_job_id: workflow_job_id,
        conclusion: Buildkite.conclusion_for(outcome(params)),
        started_at: epoch_datetime(Map.get(params, "started_at")),
        ended_at: epoch_datetime(Map.get(params, "finished_at"))
      }

      case Buildkite.record_job_finished(runner_name, account_id, report) do
        :ok ->
          send_resp(conn, :no_content, "")

        {:error, reason} ->
          Logger.error("runners: buildkite finish report failed",
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
        render_error(conn, error, "buildkite finish report")
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

  defp epoch_datetime(value) when is_number(value), do: value |> round() |> DateTime.from_unix!()
  defp epoch_datetime(_value), do: nil

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
end
