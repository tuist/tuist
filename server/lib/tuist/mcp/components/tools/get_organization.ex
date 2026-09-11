defmodule Tuist.MCP.Components.Tools.GetOrganization do
  @moduledoc """
  Get an organization's member directory and, for administrators, pending invitations.
  """

  use Tuist.MCP.Tool,
    name: "get_organization",
    title: "Get Organization",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The organization account handle."}
      },
      "required" => ["account_handle"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "integer"},
        "handle" => %{"type" => "string"},
        "plan" => %{"type" => "string"},
        "members" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "integer"},
              "email" => %{"type" => "string"},
              "name" => %{"type" => "string"},
              "role" => %{"type" => "string"}
            },
            "required" => ["id", "email", "name", "role"],
            "additionalProperties" => false
          }
        },
        "invitations" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "integer"},
              "invitee_email" => %{"type" => "string"},
              "role" => %{"type" => "string"},
              "expired" => %{"type" => "boolean"}
            },
            "required" => ["id", "invitee_email", "role", "expired"],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["id", "handle", "plan", "members", "invitations"],
      "additionalProperties" => false
    }

  alias Tuist.Accounts
  alias Tuist.Billing
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description do
    "Get an organization's members. Pending invitations are included only when the caller has the same administrator permission as the dashboard's Invitations tab. Invitation acceptance tokens are never returned."
  end

  @impl EMCP.Tool
  def call(conn, arguments) do
    with {:ok, account} <- MCPTool.resolve_and_authorize_account(arguments, conn.assigns, :read, :organization),
         {:ok, organization} <- organization_for_account(account) do
      MCPTool.json_response(
        %{
          id: organization.id,
          handle: account.name,
          plan: to_string(Billing.effective_plan(account)),
          members: members(organization),
          invitations: invitations(organization, account, conn.assigns)
        },
        __MODULE__
      )
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  defp organization_for_account(%{organization_id: nil}), do: {:error, "Account is not an organization."}

  defp organization_for_account(account) do
    case Accounts.get_organization_by_id(account.organization_id, preload: [:invitations]) do
      {:ok, organization} -> {:ok, organization}
      _ -> {:error, "Organization not found."}
    end
  end

  defp members(organization) do
    organization
    |> Accounts.get_organization_members_with_role()
    |> Enum.map(fn {member, role} ->
      %{id: member.id, email: member.email, name: member.account.name, role: role}
    end)
  end

  defp invitations(organization, account, assigns) do
    case MCPTool.authorize_account(assigns, account, :read, :invitation) do
      {:ok, _account} ->
        Enum.map(organization.invitations, fn invitation ->
          %{
            id: invitation.id,
            invitee_email: invitation.invitee_email,
            role: invitation.role,
            expired: Accounts.invitation_expired?(invitation)
          }
        end)

      {:error, _message} ->
        []
    end
  end
end
