defmodule TuistWeb.API.CASEventsController do
  use TuistWeb, :controller

  alias Tuist.Cache
  alias TuistWeb.Plugs.LoaderPlug

  plug LoaderPlug

  def create(%{assigns: %{selected_project: project}} = conn, %{"events" => events}) do
    analytics_events =
      Enum.map(events, fn event ->
        %{
          action: event["action"],
          size: event["size"],
          cas_id: event["cas_id"],
          project_id: project.id
        }
      end)

    Cache.create_cas_events(analytics_events)

    conn
    |> put_status(:accepted)
    |> json(%{})
  end
end
