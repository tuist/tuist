defmodule TuistWeb.RunnerPodJobsController do
  @moduledoc """
  Receives the workflow run of the job a GitHub runner started, from its
  runner VM. The guest's job-started hook records `GITHUB_RUN_ID`, and the
  dispatch poller, which holds the Pod's own ServiceAccount token, reports it
  once. Authenticated like the Pod's machine metrics (`TuistWeb.RunnerPodAuth`),
  so a Pod can only ever report for itself.

  See `Tuist.Runners.Claims.record_started_run/2` for what the report does.
  """

  use TuistWeb, :controller

  alias Tuist.Runners.Claims
  alias Tuist.Runners.Telemetry
  alias TuistWeb.RunnerPodAuth

  require Logger

  @doc """
  `POST /api/internal/runners/pods/:pod_name/job-started`

      { "run_id": 45115295366 }

  Idempotent: once the claimed job is detached, later reports change nothing.
  Answers 204 whatever the outcome, 400 without a positive integer `run_id`,
  401 for a token that is not this Pod's, and 503 without Kubernetes.
  """
  def started(conn, %{"pod_name" => pod_name} = params) when is_binary(pod_name) and pod_name != "" do
    with :ok <- RunnerPodAuth.authenticate(conn, pod_name),
         {:ok, run_id} <- parse_run_id(params) do
      case Claims.record_started_run(pod_name, run_id) do
        {:displaced, %{workflow_job_id: workflow_job_id, requeued: requeued}} ->
          Logger.warning(
            "runners: runner started a job of run #{run_id}; freed its claimed job (requeued: #{requeued})",
            pod: pod_name,
            workflow_job_id: workflow_job_id
          )

          :telemetry.execute(Telemetry.event_name_recovery(), %{count: 1}, %{kind: "displaced_by_other_run"})

        _ ->
          :ok
      end

      send_resp(conn, :no_content, "")
    else
      {:error, :invalid_run_id} ->
        conn |> put_status(:bad_request) |> json(%{error: "run_id must be a positive integer"})

      {:error, :not_in_cluster} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "kubernetes unavailable"})

      {:error, reason} ->
        Logger.warning("runners: rejected job-started report", pod: pod_name, reason: inspect(reason))
        conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})
    end
  end

  defp parse_run_id(%{"run_id" => run_id}) when is_integer(run_id) and run_id > 0, do: {:ok, run_id}
  defp parse_run_id(_params), do: {:error, :invalid_run_id}
end
