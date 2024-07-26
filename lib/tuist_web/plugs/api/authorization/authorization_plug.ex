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

  def call(conn, category) do
    action = get_action(conn)

    is_ci =
      Map.get(conn.body_params, :is_ci)

    project = EnsureProjectPresencePlug.get_project(conn)

    subject =
      Authentication.authenticated_subject(conn)

    cond do
      not is_nil(is_ci) and Authorization.can(subject, action, project, category, is_ci: is_ci) ->
        conn

      is_nil(is_ci) and Authorization.can(subject, action, project, category) ->
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

  defp get_action(conn) do
    case conn.method do
      "POST" -> :create
      "GET" -> :read
      "PUT" -> :update
      "DELETE" -> :delete
    end
  end
end
