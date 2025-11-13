defmodule TuistWeb.API.CASEventsController do
  use TuistWeb, :controller

  alias Tuist.Cache
  alias TuistWeb.Plugs.LoaderPlug

  require Logger

  plug LoaderPlug

  def create(%{assigns: %{selected_project: project}} = conn, %{"events" => events}) do
    # Map events to analytics entries with the project_id from the route
    analytics_events =
      Enum.map(events, fn event ->
        %{
          action: event["action"],
          size: event["size"],
          cas_id: event["cas_id"],
          project_id: project.id
        }
      end)

    {count, _} = Cache.create_cas_events(analytics_events)

    conn
    |> put_status(:accepted)
    |> json(%{status: "accepted", count: count})
  end
end
