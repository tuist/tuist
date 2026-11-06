defmodule AtlasWeb.NativeMoodboardController do
  use AtlasWeb, :controller

  alias Atlas.Moodboard
  alias Atlas.Moodboard.Suggestions

  def suggest(conn, params) do
    case Suggestions.suggest(params, conn.assigns.current_user, interface: "api") do
      {:ok, fields} -> json(conn, %{suggestions: fields})
      {:error, :rate_limited} -> error(conn, :too_many_requests, "rate_limited")
      {:error, _} -> error(conn, :unprocessable_entity, "invalid_capture")
    end
  end

  def capture(conn, %{"request_id" => request_id} = params) do
    case Moodboard.capture_resource(request_id, Map.delete(params, "request_id"), conn.assigns.current_user,
           interface: "api"
         ) do
      {:ok, resource} -> json(conn, %{saved: true, resource_id: resource.id})
      {:error, :capture_conflict} -> error(conn, :conflict, "capture_conflict")
      {:error, _} -> error(conn, :unprocessable_entity, "invalid_capture")
    end
  end

  defp error(conn, status, code), do: conn |> put_status(status) |> json(%{error: code})
end
