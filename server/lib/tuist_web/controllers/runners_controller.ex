defmodule TuistWeb.RunnersController do
  @moduledoc """
  Public endpoint the runner Pods poll for their JIT config.

  The flow:
    1. Pod boots, reads TUIST_RUNNER_POD_UID and TUIST_RUNNER_DISPATCH_TOKEN
       from its env (set by Tuist.Runners.PodSpec at create time).
    2. Pod GETs this endpoint with `pod_uid` + `token` query params on
       a 5 s loop until 200.
    3. We validate the token (constant-time SHA-256 compare against the
       stored hash) and return the assigned JIT config when one is
       available; 204 while the Pod is still idle.

  Tokens are 32-byte URL-safe random values. They never traverse a
  database leak — only their hashes are persisted. They never appear
  in logs or response bodies of other endpoints.
  """

  use TuistWeb, :controller

  alias Tuist.Runners

  require Logger

  def dispatch(conn, %{"pod_uid" => pod_uid, "token" => token}) when is_binary(pod_uid) and is_binary(token) do
    case Runners.get_assignment(pod_uid) do
      nil ->
        # No row at all — either the Pod was created before the
        # idle row landed (extremely narrow race), or someone is
        # probing for arbitrary pod UIDs. 401 either way.
        conn |> put_status(:unauthorized) |> json(%{error: "unknown pod"})

      assignment ->
        if Runners.token_matches?(assignment, token) do
          respond(conn, assignment)
        else
          Logger.warning("runners: dispatch token mismatch", pod_uid: pod_uid)
          conn |> put_status(:unauthorized) |> json(%{error: "invalid token"})
        end
    end
  end

  def dispatch(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing pod_uid or token"})
  end

  defp respond(conn, %{jit_config: nil}) do
    # Defensive: a row exists but jit_config is NULL. Shouldn't
    # happen — both the reconciler and the webhook handler
    # populate `jit_config` before inserting the row, and there's
    # no flow that creates an idle row anymore. Treat as 204 so
    # a transient race during create still degrades gracefully
    # (the next poll picks up the populated row).
    send_resp(conn, :no_content, "")
  end

  defp respond(conn, %{jit_config: jit} = assignment) do
    case Runners.claim_assignment(assignment) do
      {:ok, _} ->
        json(conn, %{
          encoded_jit_config: jit,
          pool: assignment.pool_name,
          owner: assignment.owner,
          repo: assignment.repo
        })

      {:error, reason} ->
        Logger.error("runners: claim failed", pod_uid: assignment.pod_uid, reason: inspect(reason))
        conn |> put_status(:internal_server_error) |> json(%{error: "claim failed"})
    end
  end
end
