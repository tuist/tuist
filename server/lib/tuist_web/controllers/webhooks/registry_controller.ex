defmodule TuistWeb.Webhooks.RegistryController do
  use TuistWeb, :controller

  alias Tuist.Registry

  def handle(conn, %{"events" => events}) when is_list(events) do
    cache_endpoint =
      conn
      |> Plug.Conn.get_req_header("x-cache-endpoint")
      |> List.first()

    if is_nil(cache_endpoint) or cache_endpoint == "" do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Missing x-cache-endpoint header"})
      |> halt()
    else
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
