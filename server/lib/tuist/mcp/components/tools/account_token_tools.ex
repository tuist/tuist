defmodule Tuist.MCP.Components.Tools.AccountTokenTools do
  @moduledoc false

  alias Tuist.MCP.Formatter

  def token_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => ["string", "null"]},
        "scopes" => %{"type" => "array", "items" => %{"type" => "string"}},
        "all_projects" => %{"type" => "boolean"},
        "expires_at" => %{"type" => ["string", "null"]},
        "inserted_at" => %{"type" => "string"},
        "project_handles" => %{"type" => "array", "items" => %{"type" => "string"}}
      },
      "required" => ["id", "name", "scopes", "all_projects", "expires_at", "inserted_at", "project_handles"],
      "additionalProperties" => false
    }
  end

  def serialize(token) do
    %{
      id: token.id,
      name: token.name,
      scopes: token.scopes,
      all_projects: token.all_projects,
      expires_at: Formatter.iso8601(token.expires_at),
      inserted_at: Formatter.iso8601(token.inserted_at),
      project_handles: Enum.map(token.projects || [], & &1.name)
    }
  end
end

defmodule Tuist.MCP.Components.Tools.ListAccountTokens do
  @moduledoc """
  List account tokens.
  """

  use Tuist.MCP.Tool,
    name: "list_account_tokens",
    title: "List Account Tokens",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{
          "type" => "string",
          "description" => "The account handle (organization or user)."
        },
        "page" => %{"type" => "integer", "description" => "Page number (default: 1)."},
        "page_size" => %{"type" => "integer", "description" => "Results per page (default: 20, max: 100)."}
      },
      "required" => ["account_handle"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "tokens" => %{"type" => "array", "items" => Tuist.MCP.Components.Tools.AccountTokenTools.token_schema()},
        "pagination_metadata" => Tuist.MCP.Tool.pagination_metadata_schema()
      },
      "required" => ["tokens", "pagination_metadata"],
      "additionalProperties" => false
    }

  alias Tuist.Accounts
  alias Tuist.MCP.Components.Tools.AccountTokenTools
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description, do: "List account tokens without exposing their secret values."

  @impl EMCP.Tool
  def call(conn, args) do
    case MCPTool.resolve_and_authorize_account(args, conn.assigns, :read, :account_token) do
      {:ok, account} ->
        {tokens, meta} =
          Accounts.list_account_tokens(account, %{
            order_by: [:inserted_at],
            order_directions: [:desc],
            page: MCPTool.page(args),
            page_size: MCPTool.page_size(args)
          })

        MCPTool.json_response(
          %{
            tokens: Enum.map(tokens, &AccountTokenTools.serialize/1),
            pagination_metadata: MCPTool.pagination_metadata(meta)
          },
          __MODULE__
        )

      {:error, message} ->
        EMCP.Tool.error(message)
    end
  end
end

defmodule Tuist.MCP.Components.Tools.GetAccountToken do
  @moduledoc """
  Get an account token's non-secret metadata.
  """

  use Tuist.MCP.Tool,
    name: "get_account_token",
    title: "Get Account Token",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{
          "type" => "string",
          "description" => "The account handle (organization or user)."
        },
        "token_id" => %{
          "type" => "string",
          "description" => "The token identifier, or a Tuist dashboard URL."
        }
      },
      "required" => ["account_handle", "token_id"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.AccountTokenTools.token_schema()

  alias Tuist.Accounts
  alias Tuist.MCP.Components.Tools.AccountTokenTools
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description, do: "Get an account token's non-secret metadata."

  @impl EMCP.Tool
  def call(conn, %{"token_id" => token_id} = args) do
    token_id = MCPTool.resource_id(token_id)

    with {:ok, account} <- MCPTool.resolve_and_authorize_account(args, conn.assigns, :read, :account_token),
         {:ok, token} <- Accounts.get_account_token(account, token_id) do
      MCPTool.json_response(AccountTokenTools.serialize(token), __MODULE__)
    else
      {:error, :not_found} -> EMCP.Tool.error("Account token not found: #{token_id}")
      {:error, message} -> EMCP.Tool.error(message)
    end
  end
end

defmodule Tuist.MCP.Components.Tools.ListProjectTokens do
  @moduledoc """
  List project tokens.
  """

  use Tuist.MCP.Tool,
    name: "list_project_tokens",
    title: "List Project Tokens",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{
          "type" => "string",
          "description" => "The account handle (organization or user)."
        },
        "project_handle" => %{"type" => "string", "description" => "The project handle."}
      },
      "required" => ["account_handle", "project_handle"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "tokens" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "inserted_at" => %{"type" => "string"}
            },
            "required" => ["id", "inserted_at"],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["tokens"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Projects

  @impl EMCP.Tool
  def description, do: "List project token metadata without exposing their secret values."

  @impl EMCP.Tool
  def call(conn, %{"account_handle" => account_handle, "project_handle" => project_handle}) do
    with project when not is_nil(project) <-
           Projects.get_project_by_account_and_project_handles(account_handle, project_handle),
         {:ok, _account} <- MCPTool.authorize_account(conn.assigns, project.account, :read, :account_token) do
      tokens =
        project
        |> Projects.get_project_tokens()
        |> Enum.map(fn token -> %{id: token.id, inserted_at: Formatter.iso8601(token.inserted_at)} end)

      MCPTool.json_response(%{tokens: tokens}, __MODULE__)
    else
      nil -> EMCP.Tool.error("Project not found: #{account_handle}/#{project_handle}")
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  def call(_conn, _args), do: EMCP.Tool.error("Provide account_handle and project_handle.")
end
