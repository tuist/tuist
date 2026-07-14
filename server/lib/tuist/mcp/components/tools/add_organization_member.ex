defmodule Tuist.MCP.Components.Tools.AddOrganizationMember do
  @moduledoc """
  Add an existing Tuist user to an organization or update an existing member's role.
  """

  use Tuist.MCP.Tool,
    name: "add_organization_member",
    title: "Add Organization Member",
    read_only_hint: false,
    destructive_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "organization_handle" => %{
          "type" => "string",
          "description" => "The organization handle."
        },
        "email" => %{
          "type" => "string",
          "description" => "The email of the existing Tuist user to add or update."
        },
        "role" => %{
          "type" => "string",
          "enum" => ["user", "admin"],
          "description" => "The role to assign to the new or existing member. Defaults to user."
        }
      },
      "required" => ["organization_handle", "email"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "integer"},
        "email" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "organization_handle" => %{"type" => "string"},
        "role" => %{"type" => "string", "enum" => ["user", "admin"]}
      },
      "required" => ["id", "email", "name", "organization_handle", "role"],
      "additionalProperties" => false
    }

  alias Tuist.Accounts
  alias Tuist.Authorization

  @impl EMCP.Tool
  def description, do: "Add an existing Tuist user to an organization or update an existing member's role."

  def execute(%{assigns: %{current_user: user}}, %{"organization_handle" => organization_handle, "email" => email} = args)
      when is_binary(organization_handle) and is_binary(email) do
    role = Map.get(args, "role", "user")
    organization_account = accessible_organization_account(user, organization_handle)

    cond do
      is_nil(organization_account) ->
        {:error, not_authorized_error()}

      Authorization.authorize(:member_update, user, organization_account.account) != :ok ->
        {:error, not_authorized_error()}

      role not in ["user", "admin"] ->
        {:error, "role must be either user or admin."}

      true ->
        add_member(organization_account.organization, organization_account.account, email, role)
    end
  end

  def execute(_conn, _args), do: {:error, "You must authenticate as a user to add organization members."}

  defp accessible_organization_account(user, organization_handle) do
    user
    |> Accounts.get_user_organization_accounts()
    |> Enum.find(&(&1.account.name == organization_handle))
  end

  defp add_member(organization, account, email, role) do
    with {:ok, member} <- Accounts.get_user_by_email(email),
         :ok <- upsert_member_role(member, organization, role) do
      {:ok,
       %{
         id: member.id,
         email: member.email,
         name: member.account.name,
         organization_handle: account.name,
         role: role
       }}
    else
      {:error, :not_found} -> {:error, "User #{email} was not found."}
    end
  end

  defp upsert_member_role(member, organization, role) do
    role = String.to_existing_atom(role)

    case Accounts.get_user_role_in_organization(member, organization) do
      nil -> Accounts.add_user_to_organization(member, organization, role: role)
      _current_role -> update_member_role(member, organization, role)
    end
  end

  defp update_member_role(member, organization, role) do
    case Accounts.update_user_role_in_organization(member, organization, role) do
      {:ok, _role} -> :ok
      result -> result
    end
  end

  defp not_authorized_error, do: "The authenticated subject is not authorized to perform this action."
end
