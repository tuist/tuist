defmodule TuistWeb.API.EnsureProjectPresencePlug do
  @moduledoc ~S"""
  A plug that ensures the presence of a project identified through the request
  parameters. When the request is absent, it returns a 404 response.
  """
  use TuistWeb, :controller
  use TuistWeb, :verified_routes

  alias Tuist.Repo
  alias Tuist.CommandEvents
  alias Tuist.Projects
  alias Tuist.Projects.Project

  def init(opts), do: opts

  def put_project(conn, %Project{} = project) do
    conn |> assign(:selected_project, project)
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
            "account_handle" => account_handle,
            "project_handle" => project_name
          }
        } = conn,
        _opts
      ) do
    assign_request_project_to_conn("#{account_handle}/#{project_name}", conn)
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
      |> Repo.preload(project: [:account])

    if is_nil(command_event) do
      conn
      |> put_status(:not_found)
      |> json(%{message: "The command event #{run_id} was not found."})
      |> halt()
    else
      conn |> assign(:selected_project, command_event.project)
    end
  end

  defp assign_request_project_to_conn(project_slug, conn) do
    project =
      case Map.get(conn.assigns, :caching, false) do
        true ->
          Tuist.Cache.get_value(
            [Atom.to_string(__MODULE__), "project", project_slug],
            [
              ttl: Map.get(conn.assigns, :cache_ttl, :timer.minutes(1)),
              cache: Map.get(conn.assigns, :cache, :tuist)
            ],
            fn ->
              Projects.get_project_by_slug(project_slug, preload: [:account])
            end
          )

        false ->
          Projects.get_project_by_slug(project_slug, preload: [:account])
      end

    case project do
      {:ok, project} ->
        conn |> assign(:selected_project, project)

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
