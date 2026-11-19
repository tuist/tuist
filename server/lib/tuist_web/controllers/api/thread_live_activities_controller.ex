defmodule TuistWeb.API.ThreadLiveActivitiesController do
  @moduledoc """
  Registers Luft's thread Live Activity (`Tuist.Push.LiveActivities`).
  Only Luft calls it, so it stays out of the OpenAPI spec the CLI's client is
  generated from.

  `PUT /api/me/thread-live-activities/:id` takes `{"token", "environment"}` and
  answers `204`, `400` for invalid input, `409` for another user's registration
  and `410` once the ID is retired (the app must start a new activity with a new
  UUID). `DELETE` retires it and always answers `204` for a valid ID.

  `PUT /api/me/thread-live-activity-starter` takes the sign-in's push-to-start
  `{"token", "environment", "profile_id"}` and answers `204` or `400`;
  `DELETE` forgets it and answers `204`.
  """
  use TuistWeb, :controller

  alias Tuist.Push.LiveActivities

  plug TuistWeb.Plugs.AppSessionPlug, apps: ["luft"]

  def update(conn, %{"id" => id} = params) do
    case LiveActivities.register(conn.assigns.app_user, conn.assigns.app_session, id, params) do
      {:ok, _registration} -> send_resp(conn, :no_content, "")
      {:error, :invalid} -> conn |> put_status(:bad_request) |> json(%{message: "Invalid Live Activity."})
      {:error, :conflict} -> conn |> put_status(:conflict) |> json(%{message: "The ID belongs to another registration."})
      {:error, :retired} -> conn |> put_status(:gone) |> json(%{message: "The ID was retired. Use a new one."})
    end
  end

  def delete(conn, %{"id" => id}) do
    case LiveActivities.unregister(conn.assigns.app_user, id) do
      :ok -> send_resp(conn, :no_content, "")
      {:error, :invalid} -> conn |> put_status(:bad_request) |> json(%{message: "Invalid Live Activity."})
    end
  end

  def update_starter(conn, params) do
    case LiveActivities.register_starter(conn.assigns.app_user, conn.assigns.app_session, params) do
      :ok -> send_resp(conn, :no_content, "")
      {:error, :invalid} -> conn |> put_status(:bad_request) |> json(%{message: "Invalid push-to-start token."})
    end
  end

  def delete_starter(conn, _params) do
    :ok = LiveActivities.unregister_starter(conn.assigns.app_user, conn.assigns.app_session)
    send_resp(conn, :no_content, "")
  end
end
