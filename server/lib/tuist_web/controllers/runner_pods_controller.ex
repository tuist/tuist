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

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.RunnerSessions

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
    with {:ok, token} <- bearer_token(conn),
         {:ok, principal} <- K8sClient.create_controller_token_review(token),
         :ok <- ensure_controller_principal(principal),
         {:ok, pod_name} <- parse_pod_name(params),
         {:ok, ended_at} <- parse_timestamp(params, "ended_at"),
         {:ok, _} <- RunnerSessions.close_by_pod_name(pod_name, ended_at) do
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

  defp ensure_controller_principal(%{namespace: ns, name: name} = principal) do
    if ns == Environment.runners_controller_namespace() and
         name == Environment.runners_controller_sa_name() do
      :ok
    else
      {:error, {:wrong_principal, principal}}
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

  defp bearer_token(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      ["bearer " <> token] when token != "" -> {:ok, token}
      _ -> {:error, :missing_bearer}
    end
  end
end
