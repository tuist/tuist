defmodule TuistWeb.RunnerBuildkiteJobsController do
  @moduledoc """
  Ingests a Buildkite job's log and outcome from the VM that ran it.

  The GitHub lane pulls both from GitHub after the fact: logs from the
  Actions Logs API, the outcome from the `workflow_job.completed`
  webhook. Neither is available here on the same terms. Buildkite's log
  endpoint lives on the REST API, which takes an organization API token
  rather than the cluster agent token, so using it would mean asking the
  customer for a second, broader credential purely so we can read back
  output that passed through our own machine on its way out.

  So the VM reports instead. `buildkite-agent` is started with
  `--enable-job-log-tmpfile`, which writes the job's log verbatim to a
  path it exports as `BUILDKITE_JOB_LOG_TMPFILE`, and a global `pre-exit`
  hook posts that file here along with the job's window and exit status.
  This is the capture point GitHub's runner does not offer: there, step
  output goes straight from the worker to GitHub over HTTP with no stable
  in-VM read point, which is why that lane pulls.

  Both endpoints authenticate as the Pod, with the same ServiceAccount
  token the Pod used to fetch its dispatch (`TuistWeb.RunnerPodAuth`), so
  a Pod can only report for itself. The job the report belongs to is
  resolved from the Pod's open session, never from the body: the
  acquisition token bound the Pod to one job at dispatch, and letting the
  body name a different one would let a compromised job write over
  another's history.
  """

  use TuistWeb, :controller

  alias Tuist.Runners.Buildkite
  alias Tuist.Runners.Buildkite.LogParser
  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.RunnerSessions
  alias TuistWeb.RunnerPodAuth

  require Logger

  @max_log_bytes 64 * 1024 * 1024

  @doc """
  `POST /api/internal/runners/pods/:pod_name/buildkite/logs`

      { "lines": ["...", "..."], "first_line_number": 1 }

  Lines are appended verbatim in the order given. The ReplacingMergeTree
  key `(workflow_job_id, line_number)` collapses a re-posted batch, so
  the hook may retry freely.
  """
  def logs(conn, %{"pod_name" => pod_name} = params) when is_binary(pod_name) and pod_name != "" do
    with :ok <- RunnerPodAuth.authenticate(conn, pod_name),
         {:ok, lines} <- parse_lines(params),
         {:ok, %{workflow_job_id: workflow_job_id, account_id: account_id}} <-
           RunnerSessions.executed_job_for_pod(pod_name) do
      lines
      |> LogParser.parse(
        params |> Map.get("first_line_number", 1) |> to_integer(1),
        DateTime.utc_now()
      )
      |> Enum.map(&Map.merge(&1, %{workflow_job_id: workflow_job_id, account_id: account_id}))
      |> JobLogs.append()

      send_resp(conn, :no_content, "")
    else
      :error ->
        # No open session for this Pod. Its job is already closed, or the
        # Pod is reporting after a reap; either way there is nothing left
        # to attach the lines to.
        send_resp(conn, :no_content, "")

      error ->
        render_error(conn, error, "buildkite log ingest")
    end
  end

  def logs(conn, _params), do: conn |> put_status(:bad_request) |> json(%{error: "invalid pod_name"})

  @doc """
  `POST /api/internal/runners/pods/:pod_name/buildkite/finish`

      {
        "exit_status": 0,
        "cancelled": false,
        "started_at": 1750684800.0,
        "finished_at": 1750684860.0
      }

  Closes the lifecycle row, frees the account's concurrency slot and
  records the billable window. A failed write is reported as 500 rather
  than swallowed: the window is recorded nowhere else, and the hook
  retries on a non-2xx.
  """
  def finish(conn, %{"pod_name" => pod_name} = params) when is_binary(pod_name) and pod_name != "" do
    with :ok <- RunnerPodAuth.authenticate(conn, pod_name),
         {:ok, %{workflow_job_id: workflow_job_id, account_id: account_id, runner_name: runner_name}} <-
           RunnerSessions.executed_job_for_pod(pod_name) do
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
            pod_name: pod_name,
            workflow_job_id: workflow_job_id,
            reason: inspect(reason)
          )

          conn |> put_status(:internal_server_error) |> json(%{error: "finish report failed"})
      end
    else
      :error ->
        send_resp(conn, :no_content, "")

      error ->
        render_error(conn, error, "buildkite finish report")
    end
  end

  def finish(conn, _params), do: conn |> put_status(:bad_request) |> json(%{error: "invalid pod_name"})

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

  defp epoch_datetime(value) when is_number(value) do
    value |> round() |> DateTime.from_unix!()
  end

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

  defp render_error(conn, {:error, :unauthenticated}, context) do
    Logger.warning("runners: tokenreview rejected token on #{context}")
    conn |> put_status(:unauthorized) |> json(%{error: "invalid token"})
  end

  defp render_error(conn, {:error, :not_service_account}, context) do
    Logger.warning("runners: tokenreview principal is not an SA on #{context}")
    conn |> put_status(:unauthorized) |> json(%{error: "not a service account"})
  end

  defp render_error(conn, {:error, {:wrong_principal, %{namespace: ns, name: name}}}, context) do
    Logger.warning("runners: unauthorized principal on #{context}",
      principal_namespace: ns,
      principal_name: name
    )

    conn |> put_status(:unauthorized) |> json(%{error: "unauthorized principal"})
  end

  defp render_error(conn, {:error, :not_in_cluster}, _context) do
    conn |> put_status(:service_unavailable) |> json(%{error: "kubernetes unavailable"})
  end

  defp render_error(conn, {:error, {:invalid_field, field}}, _context) do
    conn |> put_status(:bad_request) |> json(%{error: "invalid #{field}"})
  end

  defp render_error(conn, {:error, reason}, context) do
    Logger.error("runners: #{context} failed", reason: inspect(reason))
    conn |> put_status(:internal_server_error) |> json(%{error: "#{context} failed"})
  end
end
