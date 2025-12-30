defmodule TuistWeb.API.ProjectTokensController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Authorization
  alias Tuist.Projects
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.ProjectToken
  alias TuistWeb.Authentication

  plug(
    OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  tags ["Project tokens"]

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
      unauthorized: {"You need to be authenticated to issue new tokens", "application/json", Error},
      forbidden: {"You need to be authorized to issue new tokens", "application/json", Error},
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def create(%{params: %{account_handle: account_handle, project_handle: project_handle}} = conn, _params) do
    current_user = Authentication.current_user(conn)

    project =
      Projects.get_project_by_account_and_project_handles(account_handle, project_handle, preload: [:account])

    cond do
      is_nil(project) ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "The project #{account_handle}/#{project_handle} was not found"})

      is_nil(current_user) or
          Authorization.authorize(:account_token_create, current_user, project.account) != :ok ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          message: "The authenticated subject is not authorized to perform this action"
        })

      true ->
        token = Projects.create_project_token(project)

        conn
        |> put_status(:ok)
        |> json(%{
          token: token
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

  def index(%{params: %{account_handle: account_handle, project_handle: project_handle}} = conn, _params) do
    current_user = Authentication.current_user(conn)

    project =
      Projects.get_project_by_account_and_project_handles(account_handle, project_handle, preload: [:account])

    cond do
      is_nil(project) ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "The project #{account_handle}/#{project_handle} was not found"})

      is_nil(current_user) or
          Authorization.authorize(:account_token_read, current_user, project.account) != :ok ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          message: "The authenticated subject is not authorized to perform this action"
        })

      true ->
        tokens =
          project
          |> Projects.get_project_tokens()
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
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      bad_request: {"The provided token ID is not valid", "application/json", Error}
    }
  )

  def delete(
        %{path_params: %{"account_handle" => account_handle, "project_handle" => project_handle, "id" => token_id}} = conn,
        _params
      ) do
    current_user = Authentication.current_user(conn)

    project =
      Projects.get_project_by_account_and_project_handles(account_handle, project_handle, preload: [:account])

    cond do
      is_nil(project) ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "The project #{account_handle}/#{project_handle} was not found"})

      is_nil(current_user) or
          Authorization.authorize(:account_token_delete, current_user, project.account) != :ok ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          message: "The authenticated subject is not authorized to perform this action"
        })

      not Tuist.UUIDv7.valid?(token_id) ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          message: "The provided token ID #{token_id} is not valid. Make sure to pass a valid identifier."
        })

      true ->
        token = Projects.get_project_token_by_id(project, token_id)

        if is_nil(token) do
          conn
          |> put_status(:not_found)
          |> json(%{
            message: "The #{account_handle}/#{project_handle} project token #{token_id} was not found"
          })
        else
          Projects.revoke_project_token(token)

          conn
          |> put_status(:no_content)
          |> json(%{})
        end
    end
  end
end
