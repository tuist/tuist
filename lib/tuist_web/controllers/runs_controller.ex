defmodule TuistWeb.RunsController do
  use TuistWeb, :controller

  alias Tuist.Authorization
  alias Tuist.CommandEvents
  alias Tuist.Repo
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Errors.UnauthorizedError

  def download(conn, %{"id" => command_event_id}) do
    user = Authentication.current_user(conn)

    command_event =
      command_event_id
      |> CommandEvents.get_command_event_by_id()
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
    |> halt()
  end
end
