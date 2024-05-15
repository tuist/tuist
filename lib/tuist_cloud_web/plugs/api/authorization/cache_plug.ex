defmodule TuistCloudWeb.API.Authorization.CachePlug do
  @moduledoc ~S"""
  A plug that authorizes API actions.
  """
  use TuistCloudWeb, :controller
  use TuistCloudWeb, :verified_routes

  alias TuistCloud.Authorization
  alias TuistCloudWeb.Authentication
  alias TuistCloudWeb.API.EnsureProjectPresencePlug

  def init(:cache), do: :cache

  def call(conn, :cache) do
    action =
      if [~p"/api/cache", ~p"/api/cache/exists"] |> Enum.member?(conn.request_path) do
        :read
      else
        :write
      end

    project = EnsureProjectPresencePlug.get_project(conn)
    subject = Authentication.authenticated_subject(conn)

    if Authorization.can(subject, action, project, :cache) do
      conn
    else
      conn
      |> put_status(403)
      |> json(%{message: "The authenticated subject is not authorized to perform this action"})
      |> halt()
    end
  end
end
