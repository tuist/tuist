defmodule TuistCloudWeb.API.EnsureProjectPresencePlug do
  @moduledoc ~S"""
  A plug that ensures the presence of a project identified through the request
  parameters. When the request is absent, it returns a 404 response.
  """
  use TuistCloudWeb, :controller
  use TuistCloudWeb, :verified_routes

  alias TuistCloud.Projects
  alias TuistCloud.Projects.Project

  @project_key :project

  def init(opts), do: opts

  def get_project(conn) do
    conn.assigns[@project_key]
  end

  def put_project(conn, %Project{} = project) do
    conn |> assign(@project_key, project)
  end

  def call(
        %{query_params: %{"project_id" => project_slug}} = conn,
        _opts
      ) do
    project = Projects.get_project_by_slug(project_slug)

    if project do
      conn |> assign(@project_key, project)
    else
      conn
      |> put_status(404)
      |> json(%{message: "The project was not found"})
      |> halt()
    end
  end
end
