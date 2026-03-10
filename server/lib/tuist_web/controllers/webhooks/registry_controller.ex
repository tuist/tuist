defmodule TuistWeb.Webhooks.RegistryController do
  use TuistWeb, :controller

  alias Tuist.Registry
  alias TuistWeb.Plugs.RequireCacheEndpointPlug

  def handle(conn, %{"events" => events}) when is_list(events) do
    conn = RequireCacheEndpointPlug.call(conn, [])

    if conn.halted do
      conn
    else
      cache_endpoint = conn.assigns.cache_endpoint

      download_events =
        Enum.map(events, fn event ->
          %{
            scope: event["scope"],
            name: event["name"],
            version: event["version"],
            cache_endpoint: cache_endpoint
          }
        end)

      Registry.create_download_events(download_events)

      conn
      |> put_status(:accepted)
      |> json(%{})
      |> halt()
    end
  end

  def handle(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Invalid payload"})
    |> halt()
  end
end
