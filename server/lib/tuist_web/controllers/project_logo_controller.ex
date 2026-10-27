defmodule TuistWeb.ProjectLogoController do
  use TuistWeb, :controller

  alias Tuist.Projects
  alias TuistWeb.Plugs.LoaderPlug

  plug LoaderPlug

  # Public: the logo is embedded in Open Graph images and needs to be reachable
  # by unauthenticated crawlers. The URL is only rendered by the project's own
  # pages, so exposure follows the same surface as those pages.
  def show(%{assigns: %{selected_project: project}} = conn, _params) do
    case Projects.read_project_logo(project) do
      {:ok, binary} ->
        content_type = Projects.project_logo_content_type(project) || "application/octet-stream"

        conn
        # A logo change lands at a new storage key, so the ?v= tag the LiveView
        # appends changes and the CDN never has to trust this file to be
        # immutable.
        |> put_resp_header("cache-control", "public, max-age=300, must-revalidate")
        |> put_resp_content_type(content_type, nil)
        |> send_resp(200, binary)

      {:error, _reason} ->
        conn
        |> put_resp_header("cache-control", "public, max-age=60")
        |> send_resp(404, "")
    end
  end
end
