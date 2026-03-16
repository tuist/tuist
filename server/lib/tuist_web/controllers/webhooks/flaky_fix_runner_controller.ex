defmodule TuistWeb.Webhooks.FlakyFixRunnerController do
  use TuistWeb, :controller

  require Logger

  def handle(conn, %{"job_id" => job_id, "status" => status} = params) do
    case status do
      "running" ->
        Logger.info("Flaky fix job #{job_id} is running on processor")

      "pr_opened" ->
        Logger.info("Flaky fix job #{job_id} opened draft PR #{Map.get(params, "pr_url")}")

      "failed" ->
        Logger.warning("Flaky fix job #{job_id} failed: #{Map.get(params, "message")}")

      _ ->
        Logger.warning("Flaky fix job #{job_id} sent unknown status #{inspect(status)}")
    end

    conn
    |> put_status(:accepted)
    |> json(%{})
    |> halt()
  end

  def handle(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Invalid payload"})
    |> halt()
  end
end
