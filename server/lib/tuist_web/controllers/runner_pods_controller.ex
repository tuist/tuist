defmodule TuistWeb.RunnerPodsController do
  @moduledoc """
  Endpoints the runners-controller hits to report Pod lifecycle
  signals that drive the per-Pod billing record in
  `Tuist.Runners.RunnerSessions`.

  Authentication: the controller presents its in-cluster
  ServiceAccount token as a `Bearer` token. The server validates
  it via the Kubernetes TokenReview API — same pattern as the
  `desired_replicas` endpoint.
  """

  use TuistWeb, :controller

  alias Tuist.Runners.Claims
  alias Tuist.Runners.InteractiveSessions
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.Telemetry
  alias Tuist.Runners.Workers.OrphanedRunnersWorker
  alias TuistWeb.RunnerControllerAuth

  require Logger

  @doc """
  `POST /api/internal/runners/pods/stopped`

  Request body:

      {
        "pod_name": "tuist-macos-xcode-26-runner-abcd1234",
        "ended_at": "2026-05-26T14:23:11.842Z"
      }

  Responses:

    * 204 — session closed (or no open session to close, treated
      as a successful no-op; see `RunnerSessions.close_by_pod_name/2`
      for the under-bill rationale).
    * 400 — malformed body / unparseable `ended_at`.
    * 401 — missing or invalid SA bearer token.
    * 503 — kubernetes apiserver unavailable (TokenReview failed).
  """
  def stopped(conn, params) do
    with :ok <- RunnerControllerAuth.authenticate(conn),
         {:ok, pod_name} <- parse_pod_name(params),
         {:ok, ended_at} <- parse_timestamp(params, "ended_at"),
         {:ok, _} <- RunnerSessions.close_by_pod_name(pod_name, ended_at),
         {:ok, _} <- InteractiveSessions.close_by_pod_name(pod_name, ended_at) do
      release_stranded_claim(pod_name)
      recover_jobs_left_running(pod_name)
      send_resp(conn, :no_content, "")
    else
      {:error, :missing_bearer} ->
        conn |> put_status(:unauthorized) |> json(%{error: "missing bearer token"})

      {:error, :unauthenticated} ->
        Logger.warning("runners: tokenreview rejected token on pods/stopped")
        conn |> put_status(:unauthorized) |> json(%{error: "invalid token"})

      {:error, :not_service_account} ->
        Logger.warning("runners: tokenreview principal is not an SA on pods/stopped")
        conn |> put_status(:unauthorized) |> json(%{error: "not a service account"})

      {:error, {:wrong_principal, %{namespace: ns, name: name}}} ->
        # Any in-cluster workload with a default-audience SA token
        # would pass `create_controller_token_review/1`, so without
        # this gate any pod in the cluster could close another
        # customer's billing session early by guessing its pod_name.
        # Lock down to the runners-controller SA specifically.
        Logger.warning("runners: unauthorized principal on pods/stopped",
          principal_namespace: ns,
          principal_name: name
        )

        conn |> put_status(:unauthorized) |> json(%{error: "unauthorized principal"})

      {:error, :not_in_cluster} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "kubernetes unavailable"})

      {:error, {:missing_field, field}} ->
        conn |> put_status(:bad_request) |> json(%{error: "missing #{field}"})

      {:error, {:invalid_timestamp, field}} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid ISO-8601 timestamp in #{field}"})

      {:error, %Ecto.Changeset{}} ->
        # Persistence failure already logged inside
        # `close_by_pod_name/2`. Return 500 so the controller
        # retries on its next reconcile.
        conn |> put_status(:internal_server_error) |> json(%{error: "persistence failed"})

      {:error, reason} ->
        Logger.error("runners: pods/stopped failed", reason: inspect(reason))
        conn |> put_status(:internal_server_error) |> json(%{error: "pods/stopped failed"})
    end
  end

  # Free the account's concurrency budget the instant a Pod stops. In
  # the common path the executing runner's `completed` webhook already
  # released the claim before the Pod halted, so this frees nothing. A
  # non-empty release means the Pod stopped while still holding one — a
  # Pod stranded because GitHub ran its claimed job on a different
  # runner, or a crash mid-job — so it is surfaced as recovery
  # telemetry rather than freed silently.
  defp release_stranded_claim(pod_name) do
    case Claims.release_by_pod_name(pod_name) do
      [] ->
        :ok

      released ->
        Logger.warning("runners: released stranded claim on pod stop", pod: pod_name)

        :telemetry.execute(
          Telemetry.event_name_recovery(),
          %{count: length(released)},
          %{kind: "stranded_claim_released"}
        )
    end
  end

  # Freeing capacity is only half the recovery: the job's lifecycle row
  # still reads `running`, which `pick_queued/2` skips. Nothing else
  # corrects that promptly — GitHub never re-announces a job it still
  # considers `queued`, and `OrphanedRunnersWorker`'s sweep will not look
  # at the row until it is 5 minutes old. So hand the worker the ids to
  # re-check now. It still asks GitHub before re-queueing, so this
  # shortens the wait without widening what we act on.
  #
  # Driven off the lifecycle rows bound to the Pod rather than off what
  # the claim release returned, because the claim is a *capacity*
  # reservation and is released by whichever event frees the slot first.
  # When the runner executed a sibling's job — the common shape, since
  # GitHub binds a JIT runner by label set and never to a specific job —
  # that sibling's `completed` webhook already released this Pod's claim
  # by executor, leaving nothing here to release while the job the Pod
  # was minted for sits at `running`. Keying on the claim delete made the
  # fast path a silent no-op for exactly that population; the Pod
  # stopping is proof the job is not executing on it either way.
  defp recover_jobs_left_running(pod_name) do
    case Jobs.list_running_for_pod(pod_name) do
      [] ->
        :ok

      running ->
        workflow_job_ids = Enum.map(running, & &1.workflow_job_id)

        Logger.warning("runners: recovering jobs left running by a stopped pod",
          pod: pod_name,
          workflow_job_ids: workflow_job_ids
        )

        :telemetry.execute(
          Telemetry.event_name_recovery(),
          %{count: length(workflow_job_ids)},
          %{kind: "pod_stop_recovery_scheduled"}
        )

        Enum.each(workflow_job_ids, &schedule_orphan_recovery(&1, pod_name))
    end
  end

  defp schedule_orphan_recovery(workflow_job_id, pod_name) do
    # `pod_name` binds the recovery to this attempt: a delayed run must
    # not act on a row that a replacement Pod has since claimed.
    %{workflow_job_id: workflow_job_id, pod_name: pod_name}
    |> OrphanedRunnersWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        # The 1-minute sweep is the backstop, so a failed insert costs
        # latency rather than correctness.
        Logger.warning("runners: failed to schedule orphan recovery on pod stop",
          pod: pod_name,
          workflow_job_id: workflow_job_id,
          reason: inspect(reason)
        )

        :error
    end
  end

  defp parse_pod_name(%{"pod_name" => pod_name}) when is_binary(pod_name) and pod_name != "", do: {:ok, pod_name}

  defp parse_pod_name(_), do: {:error, {:missing_field, "pod_name"}}

  defp parse_timestamp(params, field) do
    case Map.get(params, field) do
      nil ->
        {:error, {:missing_field, field}}

      value when is_binary(value) and value != "" ->
        case DateTime.from_iso8601(value) do
          {:ok, dt, _offset} -> {:ok, dt}
          {:error, _} -> {:error, {:invalid_timestamp, field}}
        end

      _ ->
        {:error, {:invalid_timestamp, field}}
    end
  end
end
