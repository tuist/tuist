defmodule TuistWeb.Authorization do
  @moduledoc """
  A module that provides functions for authorizing requests.
  """
  use Gettext, backend: TuistWeb.Gettext

  alias Phoenix.LiveView.Socket
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
        raise UnauthorizedError, gettext("You need to be authenticated to access this page.")

      Authorization.can(user, :read, :ops) ->
        conn

      true ->
        raise UnauthorizedError, gettext("Only operations roles can access this page.")
    end
  end

  def call(%Plug.Conn{assigns: %{current_preview: %Preview{} = preview}} = conn, [:current_user, :read, :preview]) do
    guard_can_user_read_entity(preview, conn)
  end

  def on_mount(
        [:current_user, :read, :command_event],
        _params,
        _session,
        %Socket{assigns: %{current_command_event: command_event}} = socket
      )
      when not is_nil(command_event) do
    guard_can_user_read_entity(command_event, socket)
  end

  def on_mount([:current_user, :read, :ops], _params, _session, socket) do
    user = Authentication.current_user(socket)

    cond do
      is_nil(user) ->
        raise UnauthorizedError, gettext("You need to be authenticated to access this page.")

      Authorization.can(user, :read, :ops) ->
        {:cont, socket}

      true ->
        raise UnauthorizedError, gettext("Only operations roles can access this page.")
    end
  end

  defp guard_can_user_read_entity(%Preview{} = preview, %Plug.Conn{} = conn) do
    user = Authentication.current_user(conn)
    preview = Tuist.Repo.preload(preview, :project)

    cond do
      is_nil(user) ->
        raise UnauthorizedError, gettext("You need to be authenticated to access this page.")

      Authorization.can?(:project_preview_read, user, preview.project) ->
        conn

      true ->
        raise NotFoundError,
              gettext("The page you are looking for doesn't exist or has been moved.")
    end
  end

  defp guard_can_user_read_entity(entity, %Plug.Conn{} = conn) do
    user = Authentication.current_user(conn)

    cond do
      is_nil(user) ->
        raise UnauthorizedError, gettext("You need to be authenticated to access this page.")

      Authorization.can(user, :read, entity) ->
        conn

      true ->
        raise NotFoundError,
              gettext("The page you are looking for doesn't exist or has been moved.")
    end
  end

  defp guard_can_user_read_entity(entity, %Socket{} = socket) do
    user = Authentication.current_user(socket)

    cond do
      is_nil(user) ->
        raise UnauthorizedError, gettext("You need to be authenticated to access this page.")

      Authorization.can(user, :read, entity) ->
        {:cont, socket}

      true ->
        raise NotFoundError,
              gettext("The page you are looking for doesn't exist or has been moved.")
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

    if is_nil(project) or not Authorization.can(user, :read, project, :dashboard) do
      raise NotFoundError,
            "The page you are looking for doesn't exist or has been moved."
    end
  end
end
