defmodule TuistWeb.RunsController do
  alias Tuist.Repo
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.UnauthorizedError
  alias TuistWeb.Errors.NotFoundError
  alias Tuist.Authorization
  alias Tuist.CommandEvents
  use TuistWeb, :controller

  def download(conn, %{
        "id" => command_event_id
      }) do
    user = Authentication.current_user(conn)

    command_event =
      CommandEvents.get_command_event_by_id(command_event_id)
      |> Repo.preload(:project)

    if is_nil(command_event) do
      raise NotFoundError,
            "The page you are looking for doesn't exist or has been moved."
    end

    if not Authorization.can?(:project_run_read, user, command_event.project) do
      raise UnauthorizedError,
            "You don't have permission to access this page."
    end

    url = CommandEvents.generate_result_bundle_url(command_event)

    conn
    |> redirect(external: url)
  end
end
