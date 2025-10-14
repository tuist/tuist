defmodule TuistWeb.API.Cache.Plugs.LoaderQueryPlug do
  @moduledoc """
  A plug that loads project and account from query parameters for cache endpoints.
  
  This plug expects `account_handle` and `project_handle` query parameters and will:
  - Load the project using the combined slug "account_handle/project_handle"
  - Assign `:selected_project` and `:selected_account` to the connection
  - Raise appropriate errors if the project is not found or invalid
  """
  
  use TuistWeb, :controller
  
  alias Tuist.Projects
  alias TuistWeb.Errors.BadRequestError
  alias TuistWeb.Errors.NotFoundError

  def init(opts), do: opts

  def call(
        %{query_params: %{"account_handle" => account_handle, "project_handle" => project_handle}} = conn,
        _opts
      ) do
    project_slug = "#{account_handle}/#{project_handle}"

    project = Projects.get_project_by_slug(project_slug, preload: [:account])

    case project do
      {:ok, project} ->
        conn
        |> assign(:selected_project, project)
        |> assign(:selected_account, project.account)

      {:error, :not_found} ->
        raise NotFoundError,
              gettext("The project %{project_slug} was not found.", %{project_slug: project_slug})

      {:error, :invalid} ->
        raise BadRequestError,
              gettext(
                "The project full handle %{project_slug} is invalid. It should follow the convention 'account_handle/project_handle'.",
                %{project_slug: project_slug}
              )
    end
  end

  def call(_conn, _opts) do
    raise BadRequestError, "account_handle and project_handle query parameters are required"
  end
end