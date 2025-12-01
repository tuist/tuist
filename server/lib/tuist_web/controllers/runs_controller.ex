defmodule TuistWeb.RunsController do
  use TuistWeb, :controller

  alias Tuist.Authorization
  alias Tuist.CommandEvents
  alias TuistWeb.Authentication

  def download(conn, %{"run_id" => command_event_id}) do
    user = Authentication.current_user(conn)

    with {:ok, command_event} <- CommandEvents.get_command_event_by_id(command_event_id),
         {:ok, project} <- CommandEvents.get_project_for_command_event(command_event, preload: :account),
         :ok <- Authorization.authorize(:run_read, user, project) do
      url = CommandEvents.generate_result_bundle_url(command_event)

      conn
      |> redirect(external: url)
      |> halt()
    end
  end
end
