defmodule TuistWeb.RemoteExecutionController do
  @moduledoc false
  use TuistWeb, :controller

  alias Tuist.RemoteExecution

  plug(:authorize)

  def capabilities(conn, _params) do
    case RemoteExecution.settings(conn.assigns.execution_project.account_id) do
      %{max_concurrency: concurrency, node_names: [_ | _]} = settings when concurrency > 0 ->
        json(conn, %{
          image: settings.image_tag,
          endpoint: settings.executor_endpoint,
          cas_endpoint: settings.cas_endpoint,
          max_concurrency: concurrency
        })

      _ ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{message: "execution capacity is not configured"})
    end
  end

  def create(conn, params) do
    case RemoteExecution.submit(conn.assigns.execution_project, params) do
      {:ok, operation} ->
        conn |> put_status(:accepted) |> json(operation)

      {:error, :invalid_request} ->
        conn |> put_status(:bad_request) |> json(%{message: "invalid execution request"})

      {:error, :queue_full} ->
        conn |> put_status(:too_many_requests) |> json(%{message: "execution queue is full"})

      {:error, _} ->
        conn |> put_status(:service_unavailable) |> json(%{message: "execution unavailable"})
    end
  end

  def show(conn, %{"id" => id} = params) do
    case RemoteExecution.await(conn.assigns.execution_project, id, params["after"]) do
      {:ok, operation} ->
        json(conn, operation)

      {:error, _} ->
        conn |> put_status(:not_found) |> json(%{message: "operation not found"})
    end
  end

  defp authorize(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "private, no-store")
    opts = [require_enabled: action_name(conn) != :show]

    with ["Bearer " <> token] when byte_size(token) in 1..16_384 <-
           get_req_header(conn, "authorization"),
         %{"account" => account, "project" => project} <- conn.path_params,
         {:ok, project} <- RemoteExecution.authorize(token, account, project, opts) do
      assign(conn, :execution_project, project)
    else
      _ ->
        conn |> put_status(:forbidden) |> json(%{message: "execution not authorized"}) |> halt()
    end
  end
end
