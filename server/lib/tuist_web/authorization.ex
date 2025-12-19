defmodule TuistWeb.Authorization do
  @moduledoc """
  A module that provides functions for authorizing requests.
  """
  use Gettext, backend: TuistWeb.Gettext

  alias Tuist.AppBuilds.Preview
  alias Tuist.Authorization
  alias Tuist.Projects
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Errors.UnauthorizedError

  def init(opts), do: opts

  def call(conn, [:current_user, :read, :ops]) do
    user = Authentication.current_user(conn)

    cond do
      is_nil(user) ->
        raise UnauthorizedError, dgettext("dashboard", "You need to be authenticated to access this page.")

      Authorization.authorize(:ops_read, user, :ops) == :ok ->
        conn

      true ->
        raise UnauthorizedError, dgettext("dashboard", "Only operations roles can access this page.")
    end
  end

  def call(%Plug.Conn{assigns: %{current_preview: %Preview{} = preview}} = conn, [:current_user, :read, :preview]) do
    guard_can_user_read_entity(preview, conn)
  end

  def on_mount([:current_user, :read, :ops], _params, _session, socket) do
    user = Authentication.current_user(socket)

    cond do
      is_nil(user) ->
        raise UnauthorizedError, dgettext("dashboard", "You need to be authenticated to access this page.")

      Authorization.authorize(:ops_read, user, :ops) == :ok ->
        {:cont, socket}

      true ->
        raise UnauthorizedError, dgettext("dashboard", "Only operations roles can access this page.")
    end
  end

  defp guard_can_user_read_entity(%Preview{} = preview, %Plug.Conn{} = conn) do
    user = Authentication.current_user(conn)
    preview = Tuist.Repo.preload(preview, :project)

    cond do
      is_nil(user) ->
        raise UnauthorizedError, dgettext("dashboard", "You need to be authenticated to access this page.")

      Authorization.authorize(:preview_read, user, preview.project) == :ok ->
        conn

      true ->
        raise NotFoundError,
              dgettext("dashboard", "The page you are looking for doesn't exist or has been moved.")
    end
  end

  defp guard_can_user_read_entity(entity, %Plug.Conn{} = conn) do
    user = Authentication.current_user(conn)

    cond do
      is_nil(user) ->
        raise UnauthorizedError, dgettext("dashboard", "You need to be authenticated to access this page.")

      Authorization.authorize(:command_event_read, user, entity) == :ok ->
        conn

      true ->
        raise NotFoundError,
              dgettext("dashboard", "The page you are looking for doesn't exist or has been moved.")
    end
  end

  @doc """
  Used for project routes to ensure a user can read the project.
  """
  def require_user_can_read_project(
        %{path_params: %{"account_handle" => account_handle, "project_handle" => project_handle}} = conn,
        _opts
      ) do
    user = Authentication.current_user(conn)

    require_user_can_read_project(%{
      user: user,
      account_handle: account_handle,
      project_handle: project_handle
    })

    conn
  end

  def require_user_can_read_project(%{user: user, account_handle: account_handle, project_handle: project_handle}) do
    project = Projects.get_project_by_account_and_project_handles(account_handle, project_handle)

    if is_nil(project) or Authorization.authorize(:dashboard_read, user, project) != :ok do
      raise NotFoundError,
            "The page you are looking for doesn't exist or has been moved."
    end
  end
end
