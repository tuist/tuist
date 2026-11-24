defmodule LuftServerWeb.ThreadsController do
  use LuftServerWeb, :controller

  alias LuftServer.Sessions.Session
  alias LuftServer.Threads
  alias LuftServer.Tuist.Scope

  plug :load_scope
  plug :validate_id

  def index(conn, params) do
    case Threads.list(conn.assigns.thread_scope, params["cursor"]) do
      {:ok, page} ->
        json(conn, %{
          threads: Enum.map(page.threads, &Threads.serialize/1),
          next_cursor: page.next_cursor
        })

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def show(conn, params),
    do:
      respond(
        conn,
        Threads.get(conn.assigns.thread_scope, conn.path_params["id"], before: params["before"])
      )

  def create(conn, _params) do
    respond(
      conn,
      Threads.create(
        conn.assigns.thread_scope,
        conn.assigns.session,
        conn.path_params["account_handle"],
        conn.body_params,
        execution(conn)
      )
    )
  end

  def message(conn, _params) do
    respond(
      conn,
      Threads.message(
        conn.assigns.thread_scope,
        conn.assigns.session,
        conn.path_params["id"],
        conn.body_params,
        execution(conn)
      )
    )
  end

  def update(%{body_params: %{"snooze" => value}} = conn, _params),
    do: respond(conn, Threads.snooze(conn.assigns.thread_scope, conn.path_params["id"], value))

  def update(conn, _params),
    do:
      respond(
        conn,
        Threads.archive(
          conn.assigns.thread_scope,
          conn.path_params["id"],
          conn.body_params["status"]
        )
      )

  def models(conn, _params) do
    case Threads.models(conn.assigns.thread_scope, conn.assigns.session) do
      {:ok, catalog} -> json(conn, catalog)
      {:error, reason} -> error(conn, reason)
    end
  end

  def repositories(conn, _params) do
    case Threads.repositories(
           conn.assigns.thread_scope,
           conn.assigns.session,
           conn.path_params["account_handle"]
         ) do
      {:ok, repositories} -> json(conn, %{repositories: repositories})
      {:error, reason} -> error(conn, reason)
    end
  end

  def ship_preview(conn, _params) do
    case Threads.ship_preview(conn.assigns.thread_scope, conn.path_params["id"]) do
      {:ok, preview} -> json(conn, Map.put(preview, :jam_id, preview.thread_id))
      {:error, reason} -> error(conn, reason)
    end
  end

  def reauthorize(conn, _params),
    do:
      respond(
        conn,
        Threads.reauthorize(
          conn.assigns.thread_scope,
          conn.assigns.session,
          conn.path_params["id"],
          conn.path_params["account_handle"]
        )
      )

  def ship(conn, _params),
    do:
      respond(
        conn,
        Threads.ship(
          conn.assigns.thread_scope,
          conn.assigns.session,
          conn.path_params["id"],
          conn.body_params
        )
      )

  def reconcile_ship(conn, _params),
    do:
      respond(
        conn,
        Threads.reconcile_ship(
          conn.assigns.thread_scope,
          conn.assigns.session,
          conn.path_params["id"],
          conn.body_params
        )
      )

  # Execution integration is an internal assign, never a client parameter.
  # Unconfigured controllers reject new work rather than pretending it ran.
  defp execution(conn),
    do: [
      execution:
        Map.get(
          conn.assigns,
          :threads_execution,
          Application.get_env(:luft_server, :threads_execution, LuftServer.Threads.Execution)
        )
    ]

  defp load_scope(conn, _opts) do
    with %Session{} = session <- conn.assigns[:session],
         handle when is_binary(handle) <- conn.path_params["account_handle"],
         {:ok, scope} <- Scope.load(session, handle),
         :ok <- Threads.authorize_reader(scope) do
      assign(conn, :thread_scope, scope)
    else
      {:error, reason} -> conn |> error(reason) |> halt()
      _ -> conn |> error(:unauthenticated) |> halt()
    end
  end

  defp validate_id(conn, _opts) do
    case conn.path_params["id"] do
      nil ->
        conn

      id ->
        case Ecto.UUID.cast(id) do
          {:ok, _} -> conn
          :error -> conn |> error(:not_found) |> halt()
        end
    end
  end

  defp respond(conn, {:ok, thread}), do: json(conn, Threads.serialize(thread))
  defp respond(conn, {:error, reason}), do: error(conn, reason)

  defp error(conn, reason) when reason in [:not_found, :forbidden],
    do: conn |> put_status(:not_found) |> json(%{message: "Not found."})

  defp error(conn, reason) when reason in [:unauthorized, :unauthenticated, :reauthenticate],
    do: conn |> put_status(:unauthorized) |> json(%{error: "unauthenticated"})

  defp error(conn, :tuist_unavailable),
    do: conn |> put_status(:bad_gateway) |> json(%{error: "tuist_unavailable"})

  defp error(conn, reason) when reason in [:execution_unavailable, :delegation_required],
    do:
      conn
      |> put_status(:service_unavailable)
      |> json(%{code: reason, message: "Thread execution is unavailable."})

  defp error(conn, :invalid_arguments),
    do: conn |> put_status(:bad_request) |> json(%{message: "The thread request is invalid."})

  defp error(conn, reason)
       when reason in [
              :busy,
              :archived,
              :question_answered,
              :not_working,
              :request_conflict,
              :shipping_uncertain,
              :shipping_review_stale,
              :shipping_approval_invalid,
              :tool_outcome_unknown,
              :stale_run,
              :workspace_busy,
              :workspace_unavailable,
              :shipping_preview_unavailable,
              :shipping_diff_empty_or_too_large
            ],
       do:
         conn
         |> put_status(:conflict)
         |> json(%{code: reason, message: "The thread request could not be completed."})

  # Never render provider responses, exception text or request values.
  defp error(conn, _reason),
    do:
      conn
      |> put_status(:service_unavailable)
      |> json(%{message: "Thread execution is unavailable."})
end
