defmodule TuistCloudWeb.API.ProjectsController do
  use OpenApiSpex.ControllerSpecs
  use TuistCloudWeb, :controller
  alias TuistCloudWeb.Authentication
  alias OpenApiSpex.Schema
  alias TuistCloudWeb.API.Schemas.{Project, Error}
  alias TuistCloud.Projects
  alias TuistCloud.Accounts
  alias TuistCloud.Authorization

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistCloudWeb.RenderAPIErrorPlug
  )

  operation(:create,
    summary: "Create a new project.",
    operation_id: "createProject",
    request_body:
      {"Projects params", "application/json",
       %Schema{
         type: :object,
         properties: %{
           name: %Schema{
             type: :string,
             description: "The name of the project that should be created."
           },
           organization: %Schema{
             type: :string,
             description:
               "Organization to create the project with. If not specified, the project will be created with the current user's personal account."
           }
         },
         required: [:name]
       }},
    responses: %{
      ok: {"The project was created", "application/json", Project},
      bad_request: {"The account was not found", "application/json", Error},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error}
    }
  )

  def create(
        %{
          body_params:
            %{
              name: name
            } = body_params
        } = conn,
        _params
      ) do
    user = Authentication.current_user(conn)
    organization_param = Map.get(body_params, :organization, nil)

    account =
      case organization_param do
        nil -> Accounts.get_account_from_user(user)
        organization -> Accounts.get_account_by_handle(organization)
      end

    cond do
      not is_nil(organization_param) and is_nil(account) ->
        conn
        |> put_status(:not_found)
        |> json(%Error{message: "The organization #{organization_param} was not found"})

      !Authorization.can(user, :create, account, :project) ->
        conn
        |> put_status(:forbidden)
        |> json(%Error{
          message: "You don't have permission to create projects for the #{account.name} account."
        })

      # String.contains?(name, ".") ->
      #   conn
      #   |> put_status(:bad_request)
      #   |> json(%Error{
      #     message:
      #       "Project name can't contain a dot. Please use a different name, such as #{String.replace(name, ".", "-")}."
      #   })

      Projects.get_project_by_account_and_project_name(account.name, name) ->
        conn
        |> put_status(:bad_request)
        |> json(%Error{message: "Project already exists."})

      true ->
        try do
          project =
            Projects.create_project(%{
              name: name,
              account: account
            })

          conn
          |> put_status(:ok)
          |> json(%{
            id: project.id,
            full_name: Projects.get_project_slug_from_id(project.id),
            token: project.token
          })
        rescue
          e in Ecto.InvalidChangesetError ->
            message =
              Ecto.Changeset.traverse_errors(e.changeset, fn {message, _opts} -> message end)
              |> Enum.flat_map(fn {_key, value} -> value end)
              |> hd

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
         }}
    }
  )

  def index(conn, _params) do
    user = Authentication.current_user(conn)

    projects =
      Projects.get_all_project_accounts(user)
      |> Enum.map(fn project_account ->
        %{
          id: project_account.project.id,
          full_name: project_account.handle,
          token: project_account.project.token
        }
      end)

    conn
    |> put_status(:ok)
    |> json(%{projects: projects})
  end

  operation(:show,
    summary: "Returns a project based on the handle.",
    operation_id: "showProject",
    parameters: [
      account_name: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the account that the project belongs to."
      ],
      project_name: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the project to show"
      ]
    ],
    responses: %{
      ok: {"The project to show", "application/json", Project},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def show(
        %{
          path_params: %{
            "account_name" => account_name,
            "project_name" => project_name
          }
        } = conn,
        _params
      ) do
    user = Authentication.current_user(conn)
    account = Accounts.get_account_by_handle(account_name)

    project =
      if is_nil(account),
        do: nil,
        else: Projects.get_project_by_account_and_project_name(account.name, project_name)

    cond do
      is_nil(account) ->
        conn
        |> put_status(:not_found)
        |> json(%Error{message: "Account #{account_name} not found."})

      !Authorization.can(user, :read, account, :project) ->
        conn
        |> put_status(:forbidden)
        |> json(%Error{
          message: "You don't have permission to read the #{project.name} project."
        })

      is_nil(project) ->
        conn
        |> put_status(:not_found)
        |> json(%Error{message: "Project #{account_name}/#{project_name} not found."})

      !is_nil(project) ->
        conn
        |> put_status(:ok)
        |> json(%{
          id: project.id,
          full_name: "#{account.name}/#{project.name}",
          token: project.token
        })
    end
  end

  operation(:delete,
    summary: "Deletes a project with a given id.",
    operation_id: "deleteProject",
    parameters: [
      id: [
        in: :path,
        type: :number,
        required: true,
        description: "The id of the project to delete."
      ]
    ],
    responses: %{
      no_content: "The project was successfully deleted.",
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def delete(
        %{
          path_params: %{
            "id" => id
          }
        } = conn,
        _params
      ) do
    user = Authentication.current_user(conn)
    project_account = Projects.get_project_account_by_project_id(id)

    cond do
      is_nil(project_account) ->
        conn
        |> put_status(:not_found)
        |> json(%Error{message: "Project not found."})

      !Authorization.can(user, :delete, project_account.account, :project) ->
        conn
        |> put_status(:forbidden)
        |> json(%Error{
          message: "You don't have permission to delete the #{project_account.handle} project."
        })

      project_account ->
        Projects.delete_project(project_account.project)

        conn
        |> send_resp(:no_content, "")
    end
  end
end
