defmodule AtlasWeb.OrbitLiveActivityController do
  use AtlasWeb, :controller

  alias Atlas.Push.OrbitLiveActivity
  alias Atlas.RateLimit
  alias AtlasWeb.Plugs.NativeOAuthClient

  plug NativeOAuthClient
  plug :rate_limit when action in [:update, :delete]

  def show(conn, _params), do: json(conn, OrbitLiveActivity.snapshot(conn.assigns.current_user))

  def update(conn, %{"registration_id" => id}) do
    case OrbitLiveActivity.register(conn.assigns.current_user, conn.assigns.oauth_client_id, id, conn.body_params) do
      :ok -> json(conn, %{registered: true})
      {:error, reason} -> error(conn, reason)
    end
  end

  def delete(conn, %{"registration_id" => id}) do
    case OrbitLiveActivity.unregister(conn.assigns.current_user, conn.assigns.oauth_client_id, id) do
      :ok -> json(conn, %{deleted: true})
      {:error, reason} -> error(conn, reason)
    end
  end

  defp error(conn, :invalid), do: conn |> put_status(:bad_request) |> json(%{error: "invalid_live_activity"})
  defp error(conn, :retired), do: conn |> put_status(:conflict) |> json(%{error: "registration_retired"})
  defp error(conn, :conflict), do: conn |> put_status(:conflict) |> json(%{error: "registration_conflict"})
  defp error(conn, :session_ended), do: conn |> put_status(:unauthorized) |> json(%{error: "session_ended"})
  defp error(conn, _reason), do: conn |> put_status(:service_unavailable) |> json(%{error: "live_activity_unavailable"})

  defp rate_limit(conn, _opts) do
    case RateLimit.hit("orbit_live_activity:#{conn.assigns.current_user.id}", :timer.hours(1), 120) do
      {:allow, _} -> conn
      {:deny, _} -> conn |> put_status(:too_many_requests) |> json(%{error: "rate_limited"}) |> halt()
    end
  end
end
