defmodule TuistWeb.API.ProjectVCSConnectionController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.VCS
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.ProjectVCSConnection
  alias TuistWeb.Authentication

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, {:project, :project, :update})

  tags ["Projects"]

  @path_parameters [
    account_handle: [in: :path, type: :string, required: true, description: "The handle of the project's account."],
    project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."]
  ]

  operation(:update,
    summary: "Link a project to a GitHub repository.",
    description:
      "Links the project to a repository that the account's GitHub App installation can access and adopts the repository's default branch. Linking a project to the repository it is already linked to returns the existing link.",
    operation_id: "connectProjectRepository",
    parameters: @path_parameters,
    request_body:
      {"The repository to link", "application/json",
       %Schema{
         type: :object,
         properties: %{
           repository_full_handle: %Schema{
             type: :string,
             pattern: "^[\\w\\-\\.]+/[\\w\\-\\.]+$",
             description: "The repository's full handle, in the format owner/name.",
             example: "tuist/tuist"
           }
         },
         required: [:repository_full_handle]
       }},
    responses: %{
      ok: {"The project's repository link", "application/json", ProjectVCSConnection},
      bad_request: {"The request is invalid", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project was not found", "application/json", Error},
      conflict: {"The project is already linked to another repository", "application/json", Error},
      unprocessable_entity:
        {"The account has no GitHub App installation, or the installation can't access the repository",
         "application/json", Error},
      too_many_requests: Responses.authorization_throttled(),
      bad_gateway: {"GitHub couldn't be reached to check the installation's repositories", "application/json", Error}
    }
  )

  def update(%{assigns: %{selected_project: project}, body_params: %{repository_full_handle: handle}} = conn, _params) do
    case VCS.connect_github_repository(project, handle, created_by_id: actor_id(conn)) do
      {:ok, connection} ->
        json(conn, serialize(connection))

      {:error, reason} ->
        conn
        |> put_status(error_status(reason))
        |> json(%{message: VCS.connect_github_repository_error(reason, handle)})
    end
  end

  defp error_status({:already_connected, _connection}), do: :conflict
  defp error_status(:github_unavailable), do: :bad_gateway
  defp error_status(_reason), do: :unprocessable_entity

  operation(:delete,
    summary: "Unlink a project from its GitHub repository.",
    operation_id: "disconnectProjectRepository",
    parameters: @path_parameters,
    responses: %{
      no_content: "The project was unlinked.",
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project was not found or isn't linked to a GitHub repository", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def delete(%{assigns: %{selected_project: project}} = conn, _params) do
    case VCS.disconnect_github_repository(project) do
      {:ok, _connection} ->
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "The project isn't linked to a GitHub repository."})
    end
  end

  defp serialize(connection) do
    %{provider: Atom.to_string(connection.provider), repository_full_handle: connection.repository_full_handle}
  end

  defp actor_id(conn) do
    case Authentication.authenticated_subject(conn) do
      %User{id: id} -> id
      %AuthenticatedAccount{issued_by: %User{id: id}} -> id
      _ -> nil
    end
  end
end
