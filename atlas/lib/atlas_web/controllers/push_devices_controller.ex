defmodule AtlasWeb.PushDevicesController do
  use AtlasWeb, :controller

  alias Atlas.Push
  alias Atlas.RateLimit
  alias AtlasWeb.Plugs.NativeOAuthClient

  plug :no_store
  plug NativeOAuthClient
  plug :rate_limit

  @window :timer.hours(1)
  @limit 120

  # Only the JSON body is validated; path parameters are not device fields.
  def update(conn, %{"installation_id" => installation_id}) do
    case Push.register(conn.assigns.current_user, conn.assigns.oauth_client_id, installation_id, conn.body_params,
           interface: "api"
         ) do
      {:ok, installation} -> json(conn, %{registered: true, registration_id: installation.id})
      {:error, reason} -> error(conn, reason)
    end
  end

  def delete(conn, %{"installation_id" => installation_id}) do
    case Push.unregister(conn.assigns.current_user, conn.assigns.oauth_client_id, installation_id, interface: "api") do
      :ok -> json(conn, %{deleted: true})
      {:error, reason} -> error(conn, reason)
    end
  end

  defp error(conn, :invalid), do: conn |> put_status(:bad_request) |> json(%{error: "invalid_push_device"})
  defp error(conn, :retired), do: conn |> put_status(:conflict) |> json(%{error: "installation_retired"})
  defp error(conn, :conflict), do: conn |> put_status(:conflict) |> json(%{error: "installation_conflict"})

  defp error(conn, :unavailable), do: conn |> put_status(:service_unavailable) |> json(%{error: "push_unavailable"})

  defp rate_limit(conn, _opts) do
    case RateLimit.hit("push_devices:#{conn.assigns.current_user.id}", @window, @limit) do
      {:allow, _attempts} ->
        conn

      {:deny, _remaining} ->
        conn |> put_status(:too_many_requests) |> json(%{error: "rate_limited"}) |> halt()
    end
  end

  defp no_store(conn, _opts), do: put_resp_header(conn, "cache-control", "no-store")
end
