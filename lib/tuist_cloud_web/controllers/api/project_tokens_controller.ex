defmodule TuistCloudWeb.API.ProjectTokensController do
  use OpenApiSpex.ControllerSpecs
  use TuistCloudWeb, :controller
  alias TuistCloudWeb.API.Schemas.ProjectToken
  alias TuistCloud.Projects
  alias OpenApiSpex.Schema
  alias TuistCloud.Authorization
  alias TuistCloudWeb.API.Schemas.Error

  operation(:create,
    summary: "Create a new project token.",
    description: "This endpoint returns a new project token.",
    operation_id: "createProjectToken",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The account handle."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The project handle."
      ]
    ],
    responses: %{
      ok: {
        "A project token was generated",
        "application/json",
        %Schema{
          title: "ProjectFullToken",
          description: "A new project token.",
          type: :object,
          properties: %{
            token: %Schema{
              type: :string,
              description: "The generated project token."
            }
          },
          required: [:token]
        }
      },
      unauthorized:
        {"You need to be authenticated to issue new tokens", "application/json", Error},
      forbidden: {"You need to be authorized to issue new tokens", "application/json", Error},
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def create(
        %{
          path_params: %{"account_handle" => account_handle, "project_handle" => project_handle},
          assigns: %{current_user: current_user}
        } = conn,
        _params
      ) do
    project =
      Projects.get_project_by_account_and_project_handles(account_handle, project_handle,
        preloads: [:account]
      )

    cond do
      is_nil(project) ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "The project #{account_handle}/#{project_handle} was not found"})

      not Authorization.can(current_user, :create, project.account, :token) ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          message: "The authenticated subject is not authorized to perform this action"
        })

      true ->
        project_token = Projects.create_project_token(project)

        conn
        |> put_status(:ok)
        |> json(%{
          project_token: project_token
        })
    end
  end

  operation(:index,
    summary: "List all project tokens.",
    description: "This endpoint returns all tokens for a given project.",
    operation_id: "listProjectTokens",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The account handle."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The project handle."
      ]
    ],
    responses: %{
      ok: {
        "A list of project tokens.",
        "application/json",
        %Schema{
          title: "Tokens",
          description: "A list of project tokens.",
          type: :object,
          properties: %{
            tokens: %Schema{
              type: :array,
              items: ProjectToken
            }
          },
          required: [:tokens]
        }
      },
      unauthorized: {"You need to be authenticated to list tokens", "application/json", Error},
      forbidden: {"You need to be authorized to list tokens", "application/json", Error},
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def index(
        %{
          path_params: %{"account_handle" => account_handle, "project_handle" => project_handle},
          assigns: %{current_user: current_user}
        } = conn,
        _params
      ) do
    project =
      Projects.get_project_by_account_and_project_handles(account_handle, project_handle,
        preloads: [:account]
      )

    cond do
      is_nil(project) ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "The project #{account_handle}/#{project_handle} was not found"})

      not Authorization.can(current_user, :read, project.account, :token) ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          message: "The authenticated subject is not authorized to perform this action"
        })

      true ->
        tokens =
          Projects.get_project_tokens(project)
          |> Enum.map(
            &%{
              id: &1.id,
              inserted_at: &1.inserted_at
            }
          )

        conn
        |> put_status(:ok)
        |> json(%{
          tokens: tokens
        })
    end
  end

  operation(:delete,
    summary: "Revokes a project token.",
    operation_id: "revokeProjectToken",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The account handle."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The project handle."
      ],
      id: [
        in: :path,
        type: :string,
        required: true,
        description: "The ID of the project token"
      ]
    ],
    responses: %{
      no_content: "The project token was revoked",
      not_found: {"The project token was not found", "application/json", Error},
      unauthorized:
        {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error}
    }
  )

  def delete(
        %{
          path_params: %{
            "account_handle" => account_handle,
            "project_handle" => project_handle,
            "id" => token_id
          },
          assigns: %{current_user: current_user}
        } = conn,
        _params
      ) do
    project =
      Projects.get_project_by_account_and_project_handles(account_handle, project_handle,
        preloads: [:account]
      )

    token =
      if is_nil(project) do
        nil
      else
        Projects.get_project_token_by_id(project, token_id)
      end

    cond do
      is_nil(project) ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "The project #{account_handle}/#{project_handle} was not found"})

      is_nil(token) ->
        conn
        |> put_status(:not_found)
        |> json(%{
          message:
            "The #{account_handle}/#{project_handle} project token #{token_id} was not found"
        })

      not Authorization.can(current_user, :delete, project.account, :token) ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          message: "The authenticated subject is not authorized to perform this action"
        })

      true ->
        Projects.revoke_project_token(token)

        conn
        |> put_status(:no_content)
        |> json(%{})
    end
  end
end
