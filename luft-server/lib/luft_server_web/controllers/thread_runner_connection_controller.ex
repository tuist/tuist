defmodule LuftServerWeb.ThreadRunnerConnectionController do
  @moduledoc "Machine-authenticated polling and answers; route parameters must not be logged."
  use LuftServerWeb, :controller

  alias LuftServer.Threads.Runners

  @max_wait_ms 25_000

  plug :authenticate

  def poll(conn, params) do
    wait =
      case Integer.parse(to_string(params["wait_ms"] || "")) do
        {value, ""} -> value |> max(0) |> min(@max_wait_ms)
        _ -> @max_wait_ms
      end

    json(conn, %{requests: Runners.poll(conn.assigns.runner, conn.body_params, wait)})
  end

  def respond(conn, %{"id" => id}) do
    case Runners.respond(conn.assigns.runner, id, conn.body_params) do
      :ok ->
        send_resp(conn, :no_content, "")

      {:error, _} ->
        conn |> put_status(:gone) |> json(%{message: "The request is no longer waiting."})
    end
  end

  defp authenticate(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, runner} <- Runners.authenticate(token) do
      assign(conn, :runner, runner)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{message: "Register this runner again from Luft."})
        |> halt()
    end
  end
end
