defmodule TuistWeb.Webhooks.RegistryController do
  use TuistWeb, :controller

  alias Tuist.Registry

  def handle(conn, %{"events" => events}) when is_list(events) do
    download_events =
      Enum.map(events, fn event ->
        %{
          scope: event["scope"],
          name: event["name"],
          version: event["version"]
        }
      end)

    Registry.create_download_events(download_events)

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
