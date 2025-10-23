defmodule TuistWeb.API.ProjectsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.Projects
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.Project
  alias TuistWeb.Authentication

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  tags ["Projects"]

  operation(:create,
    summary: "Create a new project.",
    operation_id: "createProject",
    request_body:
      {"Projects params", "application/json",
       %Schema{
         type: :object,
         properties: %{
           full_handle: %Schema{
             type: :string,
             description: "The full handle of the project that should be created.",
             example: "tuist/tuist"
           },
           name: %Schema{
             type: :string,
             description: "The name of the project that should be created.",
             deprecated: true
           },
           organization: %Schema{
             type: :string,
             description:
               "Organization to create the project with. If not specified, the project will be created with the current user's personal account.",
             deprecated: true
           }
         }
       }},
    responses: %{
      ok: {"The project was created", "application/json", Project},
      bad_request: {"The account was not found", "application/json", Error},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error}
    }
  )

  def create(%{body_params: body_params} = conn, _params) do
    user = Authentication.current_user(conn)
    organization_handle = Map.get(body_params, :organization, nil)
    project_handle = Map.get(body_params, :name, nil)
    full_handle = Map.get(body_params, :full_handle, nil)

    handles =
      if is_nil(project_handle) do
        Projects.get_project_and_account_handles_from_full_handle(full_handle)
      else
        if is_nil(organization_handle) do
          {:ok, %{project_handle: project_handle, account_handle: user.account.name}}
        else
          {:ok, %{project_handle: project_handle, account_handle: organization_handle}}
        end
      end

    case handles do
      {:error, :invalid_full_handle} ->
        conn
        |> put_status(:bad_request)
        |> json(%Error{
          message: "The project full handle #{full_handle} is not in the format of account-handle/project-handle."
        })

      {:ok, handles} ->
        create_project_with_project_and_account_handles(conn, handles)
    end
  end

  defp create_project_with_project_and_account_handles(conn, %{
         project_handle: project_handle,
         account_handle: account_handle
       }) do
    user = Authentication.current_user(conn)
    account = Accounts.get_account_by_handle(account_handle)

    cond do
      is_nil(account) ->
        conn
        |> put_status(:not_found)
        |> json(%Error{message: "The account #{account_handle} was not found"})

      Authorization.authorize(:project_create, user, account) != :ok ->
        conn
        |> put_status(:forbidden)
        |> json(%Error{
          message: "You don't have permission to create projects for the #{account.name} account."
        })

      Projects.get_project_by_account_and_project_handles(
        account_handle,
        project_handle
      ) ->
        conn
        |> put_status(:bad_request)
        |> json(%Error{message: "Project already exists."})

      true ->
        try do
          project =
            Projects.create_project!(%{
              name: project_handle,
              account: account
            })

          conn
          |> put_status(:ok)
          |> json(%{
            id: project.id,
            full_name: Projects.get_project_slug_from_id(project.id),
            token: project.token,
            default_branch: project.default_branch,
            repository_url: Projects.get_repository_url(project),
            visibility: project.visibility
          })
        rescue
          e in Ecto.InvalidChangesetError ->
            message =
              e.changeset
              |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
              |> Enum.flat_map(fn {_key, value} -> value end)
              |> hd()

            conn
            |> put_status(:bad_request)
            |> json(%Error{message: message})
        end
    end
  end

  operation(:index,
    summary: "List projects the authenticated user has access to.",
    operation_id: "listProjects",
    responses: %{
      ok:
        {"List of projects", "application/json",
         %Schema{
           type: :object,
           properties: %{
             projects: %Schema{
               type: :array,
               items: Project
             }
           },
           required: [:projects]
         }},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error}
    }
  )

  def index(conn, _params) do
    subject = Authentication.authenticated_subject(conn)

    if is_nil(subject) do
      conn
      |> put_status(:unauthorized)
      |> json(%Error{message: "You need to be authenticated to access this resource."})
    else
      projects =
        subject
        |> Projects.get_all_project_accounts()
        |> Enum.map(fn project_account ->
          %{
            id: project_account.project.id,
            full_name: project_account.handle,
            token: project_account.project.token,
            default_branch: project_account.project.default_branch,
            visibility: project_account.project.visibility
          }
        end)

      conn
      |> put_status(:ok)
      |> json(%{projects: projects})
    end
  end

  operation(:show,
    summary: "Returns a project based on the handle.",
    operation_id: "showProject",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the account that the project belongs to."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the project to show"
      ]
    ],
    responses: %{
      ok: {"The project to show", "application/json", Project},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def show(%{path_params: %{"account_handle" => account_handle, "project_handle" => project_handle}} = conn, _params) do
    user = Authentication.current_user(conn)
    account = Accounts.get_account_by_handle(account_handle)

    project =
      if is_nil(account),
        do: nil,
        else: Projects.get_project_by_account_and_project_handles(account.name, project_handle)

    cond do
      is_nil(account) ->
        conn
        |> put_status(:not_found)
        |> json(%Error{message: "Account #{account_handle} not found."})

      Authorization.authorize(:project_read, user, account) != :ok ->
        conn
        |> put_status(:forbidden)
        |> json(%Error{
          message: "You don't have permission to read the #{project.name} project."
        })

      is_nil(project) ->
        conn
        |> put_status(:not_found)
        |> json(%Error{message: "Project #{account_handle}/#{project_handle} not found."})

      !is_nil(project) ->
        Tuist.PubSub.broadcast(%{user: user}, "projects.#{project.id}", :show)

        conn
        |> put_status(:ok)
        |> json(%{
          id: project.id,
          full_name: "#{account.name}/#{project.name}",
          token: project.token,
          default_branch: project.default_branch,
          repository_url: Projects.get_repository_url(project),
          visibility: project.visibility
        })
    end
  end

  operation(:update,
    summary: "Updates a project",
    description: "Updates a project with given parameters.",
    operation_id: "updateProject",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project's account."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project to update."
      ]
    ],
    request_body:
      {"Project update params", "application/json",
       %Schema{
         type: :object,
         properties: %{
           default_branch: %Schema{
             type: :string,
             description: "The default branch for the project."
           },
           visibility: %Schema{
             type: :string,
             enum: ["public", "private"],
             description:
               "The visibility of the project. Public projects are visible to everyone, private projects are only visible to the project's members."
           }
         }
       }},
    responses: %{
      ok: {"The updated project", "application/json", Project},
      not_found: {"The project with the given account and project handles was not found", "application/json", Error},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      bad_request: {"The request is invalid", "application/json", Error}
    }
  )

  def update(
        %{
          path_params: %{"account_handle" => account_handle, "project_handle" => project_handle},
          body_params: body_params
        } = conn,
        _params
      ) do
    project = Projects.get_project_by_account_and_project_handles(account_handle, project_handle)
    user = Authentication.current_user(conn)

    update_project(conn, %{
      project: project,
      user: user,
      account_handle: account_handle,
      project_handle: project_handle,
      body_params: body_params
    })
  end

  defp update_project(conn, %{
         project: project,
         user: user,
         account_handle: account_handle,
         project_handle: project_handle,
         body_params: body_params
       }) do
    cond do
      is_nil(project) ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Project #{account_handle}/#{project_handle} was not found."})

      Authorization.authorize(:project_update, user, project) != :ok ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          message: "The authenticated subject is not authorized to perform this action."
        })

      not is_nil(project) ->
        {:ok, project} =
          Projects.update_project(project, %{
            default_branch: Map.get(body_params, :default_branch, project.default_branch),
            visibility: Map.get(body_params, :visibility, project.visibility)
          })

        conn
        |> put_status(:ok)
        |> json(%{
          id: project.id,
          full_name: "#{account_handle}/#{project_handle}",
          token: project.token,
          default_branch: project.default_branch,
          repository_url: Projects.get_repository_url(project),
          visibility: project.visibility
        })
    end
  end

  operation(:delete,
    summary: "Deletes a project with a given id.",
    operation_id: "deleteProject",
    parameters: [
      id: [
        in: :path,
        type: :integer,
        required: true,
        description: "The id of the project to delete."
      ]
    ],
    responses: %{
      no_content: "The project was successfully deleted.",
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def delete(%{path_params: %{"id" => id}} = conn, _params) do
    user = Authentication.current_user(conn)
    project_account = Projects.get_project_account_by_project_id(id)

    cond do
      is_nil(project_account) ->
        conn
        |> put_status(:not_found)
        |> json(%Error{message: "Project not found."})

      Authorization.authorize(:project_delete, user, project_account.account) != :ok ->
        conn
        |> put_status(:forbidden)
        |> json(%Error{
          message: "You don't have permission to delete the #{project_account.handle} project."
        })

      project_account ->
        Projects.delete_project(project_account.project)

        send_resp(conn, :no_content, "")
    end
  end
end
