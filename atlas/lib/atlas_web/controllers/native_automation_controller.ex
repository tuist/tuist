defmodule AtlasWeb.NativeAutomationController do
  use AtlasWeb, :controller

  alias Atlas.Automations
  alias Atlas.Automations.Native

  @errors %{
    forbidden: {403, "forbidden"},
    not_found: {404, "not_found"},
    result_too_large: {413, "result_too_large"},
    not_published: {409, "not_published"},
    revision_changed: {409, "revision_changed"},
    idempotency_conflict: {409, "idempotency_conflict"},
    payload_changed: {409, "payload_changed"},
    decision_not_allowed: {409, "decision_not_allowed"},
    invalid_execution_state: {409, "invalid_execution_state"}
  }

  plug :put_private_headers
  plug :require_access_token

  def workflows(conn, params), do: respond(conn, Native.workflows(conn.assigns.current_user, params))
  def workflow(conn, %{"id" => id}), do: respond(conn, Native.workflow(conn.assigns.current_user, id))
  def executions(conn, params), do: respond(conn, Native.executions(conn.assigns.current_user, params))
  def execution(conn, %{"id" => id}), do: respond(conn, Native.execution(conn.assigns.current_user, id))
  def result(conn, %{"id" => id}), do: respond(conn, Native.result(conn.assigns.current_user, id))
  def approvals(conn, params), do: respond(conn, Native.approvals(conn.assigns.current_user, params))
  def approval(conn, %{"id" => id}), do: respond(conn, Native.approval(conn.assigns.current_user, id))

  def run(conn, %{"id" => id}) do
    body = conn.body_params
    respond(conn, Native.run(conn.assigns.current_user, id, body["revision_id"], body["request_id"], body["input"]))
  end

  def decide(conn, %{"id" => id}) do
    body = conn.body_params
    respond(conn, Native.decide(conn.assigns.current_user, id, body["decision"], body["payload_digest"]))
  end

  def control(conn, %{"id" => id}) do
    actor = conn.assigns.current_user

    result =
      with :ok <- Native.identifier(id),
           command when command in ["retry", "cancel"] <- conn.body_params["command"],
           {:ok, _} <- Automations.control_run(actor, id, command, interface: "api") do
        Native.execution(actor, id)
      else
        {:error, _} = error -> error
        _ -> {:error, :invalid_input}
      end

    respond(conn, result)
  end

  defp respond(conn, {:ok, value}), do: json(conn, value)

  defp respond(conn, {:error, reason}) do
    {status, code} = Map.get(@errors, reason, {422, "invalid_input"})

    conn |> put_status(status) |> json(%{error: code})
  end

  defp require_access_token(conn, _) do
    if conn.assigns.mcp_claims["typ"] == "access_token" do
      conn
    else
      conn |> put_status(:unauthorized) |> json(%{error: "invalid_token"}) |> halt()
    end
  end

  defp put_private_headers(conn, _), do: put_resp_header(conn, "cache-control", "no-store")
end
