defmodule TuistCloudWeb.API.EnsureProjectPresencePlug do
  @moduledoc ~S"""
  A plug that ensures the presence of a project identified through the request
  parameters. When the request is absent, it returns a 404 response.
  """
  use TuistCloudWeb, :controller
  use TuistCloudWeb, :verified_routes

  alias TuistCloud.Repo
  alias TuistCloud.CommandEvents
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
        %{
          body_params: %{
            project_id: project_id
          }
        } = conn,
        _opts
      ) do
    assign_request_project_to_conn(project_id, conn)
  end

  def call(
        %{
          path_params: %{
            "account_name" => account_name,
            "project_name" => project_name
          }
        } = conn,
        _opts
      ) do
    assign_request_project_to_conn("#{account_name}/#{project_name}", conn)
  end

  def call(
        %{query_params: %{"project_id" => project_slug}} = conn,
        _opts
      ) do
    assign_request_project_to_conn(project_slug, conn)
  end

  def call(
        %{
          path_params: %{
            "run_id" => run_id
          }
        } = conn,
        _opts
      ) do
    command_event =
      CommandEvents.get_command_event_by_id(run_id)
      |> Repo.preload(:project)

    if is_nil(command_event) do
      conn
      |> put_status(:not_found)
      |> json(%{message: "The command event #{run_id} was not found."})
      |> halt()
    else
      conn |> assign(@project_key, command_event.project)
    end
  end

  defp assign_request_project_to_conn(project_slug, conn) do
    case Projects.get_project_by_slug(project_slug) do
      {:ok, project} ->
        conn |> assign(@project_key, project)

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{message: "The project #{project_slug} was not found."})
        |> halt()

      {:error, :missing_handle_or_project_name} ->
        conn
        |> put_status(401)
        |> json(%{
          message:
            "The project id \"#{project_slug}\" is missing either organization/user name or a project name. Make sure it's in the format of organization-name/project-name."
        })
        |> halt()
    end
  end
end
