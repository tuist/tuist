defmodule LuftServerWeb.NotificationsController do
  @moduledoc "ActivityKit registrations on Luft's authenticated native API; device transport remains upstream."
  use LuftServerWeb, :controller

  alias LuftServer.Notifications.Delegation
  alias LuftServer.Notifications.LiveActivities
  alias LuftServer.Notifications.Transport

  def update(conn, %{"id" => id} = params) do
    manage(conn, fn actor, session ->
      with {:ok, _} <-
             Transport.request(
               session.id,
               :put,
               "/api/me/thread-live-activities/#{encode(id)}",
               params
             ),
           {:ok, _} <- LiveActivities.register(actor, grant(session), id, params),
           do: :ok
    end)
  end

  def delete(conn, %{"id" => id}) do
    manage(conn, fn actor, session ->
      with :ok <- LiveActivities.unregister(actor, id),
           {:ok, _} <-
             Transport.request(
               session.id,
               :delete,
               "/api/me/thread-live-activities/#{encode(id)}"
             ),
           do: :ok
    end)
  end

  def update_starter(conn, params) do
    manage(conn, fn actor, session ->
      with {:ok, _} <-
             Transport.request(session.id, :put, "/api/me/thread-live-activity-starter", params),
           :ok <- LiveActivities.register_starter(actor, grant(session), params) do
        LiveActivities.thread_changed(actor.id)
      end
    end)
  end

  def delete_starter(conn, _) do
    manage(conn, fn actor, session ->
      with :ok <- LiveActivities.unregister_starter(actor, grant(session)),
           {:ok, _} <-
             Transport.request(session.id, :delete, "/api/me/thread-live-activity-starter"),
           do: :ok
    end)
  end

  defp manage(conn, fun) do
    session = conn.assigns.session

    with {id, ""} <- Integer.parse(session.user_sub),
         actor when not is_nil(actor) <- Delegation.actor(session.id, id) do
      case fun.(actor, session) do
        :ok -> send_resp(conn, 204, "")
        {:error, error} when error in [:retired, :invalid_token] -> failure(conn, 410, "retired")
        {:error, :conflict} -> failure(conn, 409, "conflict")
        {:error, :invalid} -> failure(conn, 400, "invalid")
        {:error, :unauthorized} -> failure(conn, 401, "unauthorized")
        _ -> failure(conn, 502, "tuist_unavailable")
      end
    else
      _ -> failure(conn, 401, "unauthorized")
    end
  end

  defp grant(session), do: %{app: "luft", oauth_grant_id: session.id}
  defp failure(conn, status, error), do: conn |> put_status(status) |> json(%{error: error})
  defp encode(id), do: URI.encode(id, &URI.char_unreserved?/1)
end
