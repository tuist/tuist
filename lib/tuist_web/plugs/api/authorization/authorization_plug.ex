defmodule TuistWeb.API.Authorization.AuthorizationPlug do
  @moduledoc ~S"""
  A plug that authorizes API actions.
  """
  use TuistWeb, :controller
  use TuistWeb, :verified_routes

  alias Tuist.Authorization
  alias TuistWeb.Authentication
  alias TuistWeb.API.EnsureProjectPresencePlug

  def init(:command_event), do: :command_event
  def init(:cache), do: :cache
  def init(:preview), do: :preview
  def init(:registry), do: :registry

  def call(conn, category) do
    case category do
      :command_event ->
        authorize_project(conn, :command_event)

      :cache ->
        authorize_project(conn, :cache)

      :preview ->
        authorize_project(conn, :preview)

      :registry ->
        authorize_account(conn, :registry)
    end
  end

  defp authorize_account(%{assigns: %{url_account: url_account}} = conn, category) do
    action = get_action(conn)

    subject =
      Authentication.authenticated_subject(conn)

    if authorize(subject, action, url_account, category) do
      conn
    else
      status =
        case category do
          :registry -> :unauthorized
          _ -> :forbidden
        end

      conn
      |> put_status(status)
      |> json(%{
        message: "You are not authorized to #{Atom.to_string(action)} #{Atom.to_string(category)}"
      })
      |> halt()
    end
  end

  def authorize_project(conn, category) do
    action = get_action(conn)

    is_ci =
      Map.get(conn.body_params, :is_ci)

    project =
      EnsureProjectPresencePlug.get_project(conn)

    subject =
      Authentication.authenticated_subject(conn)

    cond do
      not is_nil(is_ci) and Authorization.can(subject, action, project, category, is_ci: is_ci) ->
        conn

      is_nil(is_ci) and authorize(subject, action, project, category) ->
        conn

      true ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          message:
            "#{subject.account.name} is not authorized to #{Atom.to_string(action)} #{Atom.to_string(category)}"
        })
        |> halt()
    end
  end

  def authorize(subject, :read, project, :cache) do
    Authorization.can?(:project_cache_read, subject, project)
  end

  def authorize(subject, :read, account, :registry) do
    Authorization.can?(:account_registry_read, subject, account)
  end

  def authorize(subject, :create, account, :registry) do
    # Logging in is done via POST request
    Authorization.can?(:account_registry_read, subject, account)
  end

  def authorize(subject, :create, account, :account_token) do
    Authorization.can?(:account_token_create, subject, account)
  end

  def authorize(subject, action, project, category) do
    Authorization.can(subject, action, project, category)
  end

  defp get_action(conn) do
    case conn.method do
      "POST" -> :create
      "GET" -> :read
      "PUT" -> :update
      "DELETE" -> :delete
    end
  end
end
