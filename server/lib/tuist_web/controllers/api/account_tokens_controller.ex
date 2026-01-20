defmodule TuistWeb.API.AccountTokensController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts
  alias Tuist.Accounts.AccountToken
  alias Tuist.Authorization
  alias Tuist.Projects
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.Authentication

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.Plugs.LegacyAccountTokenScopesPlug when action == :create)

  plug(
    OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  tags ["Account tokens"]

  operation(:create,
    summary: "Create a new account token.",
    description:
      "This endpoint returns a new fine-grained account token with specified scopes and optional project restrictions.",
    operation_id: "createAccountToken",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The account handle."
      ]
    ],
    request_body:
      {"Create account token params", "application/json",
       %Schema{
         title: "CreateAccountToken",
         description: "The request to create a new account token.",
         type: :object,
         properties: %{
           scopes: %Schema{
             type: :array,
             items: %Schema{
               type: :string,
               enum: AccountToken.valid_scopes(),
               description: "A scope string in format entity:object:access_level."
             },
             description: "The scopes for the new account token.",
             example: ["project:cache:read", "project:builds:write"]
           },
           name: %Schema{
             type: :string,
             description:
               "Unique name for the token. Must contain only alphanumeric characters, hyphens, and underscores (1-32 characters)."
           },
           expires_at: %Schema{
             type: :string,
             format: "date-time",
             description: "Optional expiration datetime (ISO8601). If not set, the token never expires."
           },
           project_handles: %Schema{
             type: :array,
             items: %Schema{type: :string},
             description:
               "List of project handles to restrict access to. If not provided, the token has access to all projects."
           }
         },
         required: [:scopes]
       }},
    responses: %{
      ok: {
        "An account token was generated",
        "application/json",
        %Schema{
          title: "AccountTokenCreated",
          description: "A newly created account token.",
          type: :object,
          properties: %{
            token: %Schema{
              type: :string,
              description: "The generated account token. Store this securely - it cannot be retrieved again."
            },
            id: %Schema{type: :string, description: "The token unique identifier."},
            expires_at: %Schema{
              type: :string,
              format: "date-time",
              nullable: true,
              description: "When the token expires, if set."
            }
          },
          required: [:token, :id]
        }
      },
      unauthorized: {"You need to be authenticated to issue new tokens", "application/json", Error},
      forbidden: {"You need to be authorized to issue new tokens", "application/json", Error},
      not_found: {"The account or project was not found", "application/json", Error},
      bad_request: {"The request is invalid", "application/json", Error}
    }
  )

  def create(
        %{body_params: %{scopes: scopes} = body_params, assigns: %{selected_account: selected_account}} = conn,
        _opts
      ) do
    current_user = Authentication.current_user(conn)
    name = Map.get(body_params, :name, generate_token_name())
    expires_at = Map.get(body_params, :expires_at)
    project_handles = Map.get(body_params, :project_handles, [])
    all_projects = project_handles == []

    with :ok <- Authorization.authorize(:account_token_create, current_user, selected_account),
         {:ok, projects} <- Projects.get_projects_by_handles_for_account(selected_account, project_handles) do
      project_ids = Enum.map(projects, & &1.id)

      case Accounts.create_account_token(%{
             account: selected_account,
             scopes: scopes,
             created_by_account: current_user.account,
             name: name,
             expires_at: expires_at,
             all_projects: all_projects,
             project_ids: project_ids
           }) do
        {:ok, {token_record, token}} ->
          conn
          |> put_status(:ok)
          |> json(%{
            token: token,
            id: token_record.id,
            expires_at: token_record.expires_at
          })

        {:error, changeset} ->
          conn
          |> put_status(:bad_request)
          |> json(%{message: format_changeset_errors(changeset)})
      end
    else
      {:error, :not_found, handle} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Project #{handle} not found in account #{selected_account.name}"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "The authenticated subject is not authorized to perform this action"})

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "Invalid request"})
    end
  end

  operation(:index,
    summary: "List all account tokens.",
    description: "This endpoint returns all tokens for a given account with pagination support.",
    operation_id: "listAccountTokens",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The account handle."
      ],
      page: [
        in: :query,
        type: :integer,
        required: false,
        description: "Page number for pagination."
      ],
      page_size: [
        in: :query,
        type: :integer,
        required: false,
        description: "Number of items per page."
      ]
    ],
    responses: %{
      ok: {
        "A list of account tokens.",
        "application/json",
        %Schema{
          title: "AccountTokens",
          type: :object,
          properties: %{
            tokens: %Schema{
              type: :array,
              items: %Schema{
                type: :object,
                properties: %{
                  id: %Schema{type: :string, description: "Token unique identifier."},
                  name: %Schema{type: :string, nullable: true, description: "Friendly name for the token."},
                  scopes: %Schema{
                    type: :array,
                    items: %Schema{type: :string, enum: AccountToken.valid_scopes()},
                    description: "Token scopes."
                  },
                  all_projects: %Schema{type: :boolean, description: "Whether token has access to all projects."},
                  expires_at: %Schema{
                    type: :string,
                    format: "date-time",
                    nullable: true,
                    description: "When the token expires."
                  },
                  inserted_at: %Schema{type: :string, format: "date-time", description: "When the token was created."},
                  project_handles: %Schema{
                    type: :array,
                    items: %Schema{type: :string},
                    description: "List of project handles the token can access (when all_projects is false)."
                  }
                },
                required: [:id, :scopes, :all_projects, :inserted_at]
              }
            },
            meta: TuistWeb.API.Schemas.PaginationMetadata
          },
          required: [:tokens, :meta]
        }
      },
      unauthorized: {"You need to be authenticated to list tokens", "application/json", Error},
      forbidden: {"You need to be authorized to list tokens", "application/json", Error},
      not_found: {"The account was not found", "application/json", Error}
    }
  )

  def index(%{assigns: %{selected_account: selected_account}} = conn, params) do
    current_user = Authentication.current_user(conn)

    case Authorization.authorize(:account_token_read, current_user, selected_account) do
      :ok ->
        flop_params = %{
          order_by: [:inserted_at],
          order_directions: [:desc],
          page: Map.get(params, :page, 1),
          page_size: Map.get(params, :page_size, 20)
        }

        {tokens, meta} = Accounts.list_account_tokens(selected_account, flop_params)

        conn
        |> put_status(:ok)
        |> json(%{
          tokens: Enum.map(tokens, &format_token/1),
          meta: format_meta(meta)
        })

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "The authenticated subject is not authorized to perform this action"})
    end
  end

  operation(:delete,
    summary: "Revoke an account token.",
    description: "This endpoint revokes (deletes) an account token by name.",
    operation_id: "revokeAccountToken",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The account handle."
      ],
      token_name: [
        in: :path,
        type: :string,
        required: true,
        description: "The token name to revoke."
      ]
    ],
    responses: %{
      no_content: "The account token was revoked",
      not_found: {"The token was not found", "application/json", Error},
      unauthorized: {"You need to be authenticated to revoke tokens", "application/json", Error},
      forbidden: {"You need to be authorized to revoke tokens", "application/json", Error}
    }
  )

  def delete(%{path_params: %{"token_name" => token_name}, assigns: %{selected_account: selected_account}} = conn, _opts) do
    current_user = Authentication.current_user(conn)

    with :ok <- Authorization.authorize(:account_token_delete, current_user, selected_account),
         {:ok, token} <- Accounts.get_account_token_by_name(selected_account, token_name) do
      {:ok, _} = Accounts.delete_account_token(token)

      conn
      |> put_status(:no_content)
      |> json(%{})
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Token #{token_name} not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "The authenticated subject is not authorized to perform this action"})
    end
  end

  # Helper functions

  defp format_token(token) do
    project_handles =
      case token.projects do
        projects when is_list(projects) ->
          Enum.map(projects, & &1.name)

        _ ->
          []
      end

    %{
      id: token.id,
      name: token.name,
      scopes: token.scopes,
      all_projects: token.all_projects,
      expires_at: token.expires_at,
      inserted_at: token.inserted_at,
      project_handles: project_handles
    }
  end

  defp format_meta(meta) do
    %{
      has_next_page: meta.has_next_page?,
      has_previous_page: meta.has_previous_page?,
      current_page: meta.current_page,
      page_size: meta.page_size,
      total_count: meta.total_count,
      total_pages: meta.total_pages
    }
  end

  defp generate_token_name do
    random_suffix = 4 |> :rand.bytes() |> Base.encode16(case: :lower)
    "token-#{random_suffix}"
  end

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} ->
      "#{field}: #{Enum.join(errors, ", ")}"
    end)
  end
end
