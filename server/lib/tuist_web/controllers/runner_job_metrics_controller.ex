defmodule TuistWeb.RunnerJobMetricsController do
  @moduledoc """
  Ingests machine-metrics samples for a runner job from the runner
  metrics collector.

  ## Where the samples come from

  Unlike `runner_job_logs` (pulled from GitHub's Logs API after the
  job completes), machine metrics have no GitHub-side source — they
  describe the runner Pod/VM, which only our infrastructure can see.
  The collector samples CPU / memory / network / disk for each
  running job's Pod and POSTs batches here. It runs alongside the
  runners-controller (which already owns the Pod→`workflow_job_id`
  mapping) and authenticates with the same in-cluster ServiceAccount
  token as `pods/stopped`.

  ## Contract

      POST /api/internal/runners/jobs/:workflow_job_id/metrics
      {
        "account_id": 123,
        "samples": [
          {
            "timestamp": 1750684800.0,        // epoch seconds
            "cpu_usage_percent": 42.5,
            "cpu_iowait_percent": 1.2,        // 0 on macOS (no iowait)
            "memory_used_bytes": 7516192768,
            "memory_total_bytes": 15032385536,
            "network_bytes_in": 10485760,
            "network_bytes_out": 5242880,
            "disk_used_bytes": 48318382080,
            "disk_total_bytes": 68719476736
          }
        ]
      }

  Every metric field but `timestamp` is optional and defaults to 0,
  so a Linux-only or macOS-only collector can omit what it can't
  measure. Delivery is at-least-once; the ReplacingMergeTree
  `(workflow_job_id, timestamp)` key collapses re-POSTed batches.
  """

  use TuistWeb, :controller

  alias Tuist.Runners.JobMetrics
  alias Tuist.Runners.Jobs
  alias TuistWeb.RunnerControllerAuth

  require Logger

  @metric_fields ~w(
    cpu_usage_percent cpu_iowait_percent
    memory_used_bytes memory_total_bytes
    network_bytes_in network_bytes_out
    disk_used_bytes disk_total_bytes
  )a

  @doc """
  `POST /api/internal/runners/jobs/:workflow_job_id/metrics`

  Responses:

    * 204 — samples recorded (or an empty batch, treated as a no-op).
    * 400 — malformed body (bad ids / samples not a list / sample
      missing a numeric `timestamp`).
    * 401 — missing or invalid SA bearer token / wrong principal.
    * 404 — no job with that `(account_id, workflow_job_id)`.
    * 503 — kubernetes apiserver unavailable (TokenReview failed).
  """
  def create(conn, %{"workflow_job_id" => workflow_job_id_param} = params) do
    with :ok <- RunnerControllerAuth.authenticate(conn),
         {:ok, workflow_job_id} <- parse_id(workflow_job_id_param),
         {:ok, account_id} <- parse_account_id(params),
         {:ok, samples} <- parse_samples(params),
         {:ok, _job} <- Jobs.get_for_account(account_id, workflow_job_id) do
      :ok = JobMetrics.record(workflow_job_id, account_id, samples)
      send_resp(conn, :no_content, "")
    else
      {:error, :missing_bearer} ->
        conn |> put_status(:unauthorized) |> json(%{error: "missing bearer token"})

      {:error, :unauthenticated} ->
        Logger.warning("runners: tokenreview rejected token on job metrics")
        conn |> put_status(:unauthorized) |> json(%{error: "invalid token"})

      {:error, :not_service_account} ->
        Logger.warning("runners: tokenreview principal is not an SA on job metrics")
        conn |> put_status(:unauthorized) |> json(%{error: "not a service account"})

      {:error, {:wrong_principal, %{namespace: ns, name: name}}} ->
        Logger.warning("runners: unauthorized principal on job metrics",
          principal_namespace: ns,
          principal_name: name
        )

        conn |> put_status(:unauthorized) |> json(%{error: "unauthorized principal"})

      {:error, :not_in_cluster} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "kubernetes unavailable"})

      {:error, {:invalid_field, field}} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid #{field}"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "job not found"})

      {:error, reason} ->
        Logger.error("runners: job metrics ingest failed", reason: inspect(reason))
        conn |> put_status(:internal_server_error) |> json(%{error: "metrics ingest failed"})
    end
  end

  def create(conn, _params), do: conn |> put_status(:bad_request) |> json(%{error: "invalid workflow_job_id"})

  defp parse_id(value) when is_integer(value), do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> {:error, {:invalid_field, "workflow_job_id"}}
    end
  end

  defp parse_id(_), do: {:error, {:invalid_field, "workflow_job_id"}}

  defp parse_account_id(%{"account_id" => account_id}), do: parse_id(account_id)
  defp parse_account_id(_), do: {:error, {:invalid_field, "account_id"}}

  defp parse_samples(%{"samples" => samples}) when is_list(samples) do
    samples
    |> Enum.reduce_while({:ok, []}, fn sample, {:ok, acc} ->
      case parse_sample(sample) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
  end

  defp parse_samples(_), do: {:error, {:invalid_field, "samples"}}

  defp parse_sample(%{"timestamp" => timestamp} = sample) when is_number(timestamp) do
    metrics =
      Map.new(@metric_fields, fn field ->
        {field, numeric(Map.get(sample, Atom.to_string(field), 0))}
      end)

    {:ok, Map.put(metrics, :timestamp, timestamp)}
  end

  defp parse_sample(_), do: {:error, {:invalid_field, "sample timestamp"}}

  defp numeric(value) when is_number(value), do: value
  defp numeric(_), do: 0
end
