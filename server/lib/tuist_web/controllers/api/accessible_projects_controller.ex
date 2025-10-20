defmodule TuistWeb.API.AccessibleProjectsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Projects
  alias TuistWeb.Authentication

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  tags(["Projects"])

  operation(:index,
    summary: "List projects accessible to the authenticated subject.",
    description: "Returns the list of project full handles that the provided credentials allow access to.",
    operation_id: "listAccessibleProjects",
    responses: %{
      ok:
        {"Accessible project handles", "application/json",
         %Schema{
           type: :array,
           items: %Schema{type: :string, description: "Project full handle, e.g. account/project"},
           example: ["tuist/tuist"]
         }},
      unauthorized: {"Authentication required", "application/json", TuistWeb.API.Schemas.Error}
    }
  )

  def index(conn, _params) do
    subject = Authentication.authenticated_subject(conn)

    if is_nil(subject) do
      conn
      |> put_status(:unauthorized)
      |> json(%{message: "You need to be authenticated to access this resource."})
    else
      project_handles = Projects.list_accessible_project_full_handles(subject)
      json(conn, project_handles)
    end
  end
end
