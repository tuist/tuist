defmodule Tuist.MCP.Components.Tools.ListAccounts do
  @moduledoc """
  List accounts under which the authenticated user can create or access projects.
  """

  use Tuist.MCP.Tool,
    name: "list_accounts",
    title: "List Accounts",
    schema: %{
      "type" => "object",
      "properties" => %{},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "accounts" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "integer"},
              "handle" => %{"type" => "string"},
              "type" => %{"type" => "string", "enum" => ["personal", "organization"]},
              "can_create_projects" => %{"type" => "boolean"}
            },
            "required" => ["id", "handle", "type", "can_create_projects"],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["accounts"],
      "additionalProperties" => false
    }

  alias Tuist.Accounts
  alias Tuist.Authorization

  @impl EMCP.Tool
  def description do
    "List personal and organization account handles available to the authenticated user. Call this before create_project when the account handle is unknown."
  end

  def execute(%{assigns: %{current_user: user}}, _args) do
    own_account = Accounts.get_account_from_user(user)

    organization_accounts =
      user
      |> Accounts.get_user_organization_accounts()
      |> Enum.map(& &1.account)

    accounts =
      [own_account | organization_accounts]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1.id)
      |> Enum.map(fn account ->
        %{
          id: account.id,
          handle: account.name,
          type: if(is_nil(account.organization_id), do: "personal", else: "organization"),
          can_create_projects: Authorization.authorize(:project_create, user, account) == :ok
        }
      end)

    {:ok, %{accounts: accounts}}
  end

  def execute(_conn, _args), do: {:error, "You must authenticate as a user to list accounts."}
end
