defmodule PulseWeb.ReliabilityController do
  use PulseWeb, :controller

  alias Pulse.Reliability.Investigations

  def complete(conn, %{"id" => id}) do
    with %{"tenant" => tenant, "outcome" => outcome} <- conn.body_params,
         ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, result} <- Investigations.complete(tenant, id, token, outcome) do
      json(conn, result)
    else
      {:error, reason} -> reject(conn, reason)
      %{} -> reject(conn, :invalid_arguments)
      _ -> reject(conn, :unauthorized)
    end
  end

  defp reject(conn, {:invalid_tenant, _}), do: reject(conn, :invalid_arguments)

  defp reject(conn, reason) do
    {status, error} =
      case reason do
        :invalid_arguments -> {400, "invalid_arguments"}
        :unauthorized -> {403, "completion_rejected"}
        :completion_conflict -> {409, "completion_conflict"}
        :completion_receipt_unavailable -> {410, "completion_receipt_unavailable"}
        :query_overloaded -> {429, "completion_busy"}
        :query_timeout -> {504, "completion_timeout"}
        _ -> {503, "completion_unavailable"}
      end

    conn = if status in [429, 503], do: put_resp_header(conn, "retry-after", "1"), else: conn
    conn |> put_status(status) |> json(%{"error" => error})
  end
end
