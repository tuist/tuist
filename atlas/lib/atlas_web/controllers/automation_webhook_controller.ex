defmodule AtlasWeb.AutomationWebhookController do
  use AtlasWeb, :controller

  alias Atlas.Automations
  alias Atlas.Automations.Contract
  alias Atlas.RateLimit

  def create(conn, %{"id" => id}) do
    with {:allow, _} <- RateLimit.hit("automation-hook:#{:inet.ntoa(conn.remote_ip)}", 60_000, 60),
         ["Bearer " <> credential] <- get_req_header(conn, "authorization"),
         [delivery_id] <- get_req_header(conn, "x-delivery-id"),
         input = conn.body_params,
         true <- is_map(input),
         true <- Contract.within_budget?(input, 65_536),
         {:ok, run} <- Automations.webhook(id, credential, delivery_id, input) do
      conn |> put_status(:accepted) |> json(%{execution_id: run.id})
    else
      {:deny, _} ->
        conn |> put_status(:too_many_requests) |> json(%{error: "Too many deliveries."})

      false ->
        conn |> put_status(:payload_too_large) |> json(%{error: "Payload exceeds 64 KiB."})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "Execution identity is no longer permitted."})

      {:error, error} when is_binary(error) ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "Payload does not match the workflow contract."})

      _ ->
        conn |> put_status(:unauthorized) |> json(%{error: "Invalid webhook credentials or delivery ID."})
    end
  end
end
