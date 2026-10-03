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
        "account_handle" => %{"type" => "string", "description" => "The organization account handle."},
        "page" => %{
          "type" => "integer",
          "description" => "Page number applied to both members and invitations (default: 1)."
        },
        "page_size" => %{
          "type" => "integer",
          "description" => "Members and invitations per page (default: 20, max: 100)."
        }
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
        },
        "members_pagination_metadata" => Tuist.MCP.Tool.pagination_metadata_schema(),
        "invitations_pagination_metadata" => Tuist.MCP.Tool.pagination_metadata_schema()
      },
      "required" => [
        "id",
        "handle",
        "plan",
        "members",
        "invitations",
        "members_pagination_metadata",
        "invitations_pagination_metadata"
      ],
      "additionalProperties" => false
    }

  alias Tuist.Accounts
  alias Tuist.Billing
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description do
    "Get an organization's members, ordered by handle. Pending invitations, newest first, are included only when the caller has the same administrator permission as the dashboard's Invitations tab. Invitation acceptance tokens are never returned. Members and invitations are paginated with the same page and page_size; each list has its own pagination metadata."
  end

  @impl EMCP.Tool
  def call(conn, arguments) do
    with {:ok, account} <- MCPTool.resolve_and_authorize_account(arguments, conn.assigns, :read, :organization),
         {:ok, organization} <- organization_for_account(account) do
      page = MCPTool.page(arguments)
      page_size = MCPTool.page_size(arguments)
      {members, members_total_count} = members(organization, page, page_size)
      {invitations, invitations_total_count} = invitations(organization, account, conn.assigns, page, page_size)

      MCPTool.json_response(
        %{
          id: organization.id,
          handle: account.name,
          plan: to_string(Billing.effective_plan(account)),
          members: members,
          invitations: invitations,
          members_pagination_metadata: pagination_metadata(members_total_count, page, page_size),
          invitations_pagination_metadata: pagination_metadata(invitations_total_count, page, page_size)
        },
        __MODULE__
      )
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  defp organization_for_account(%{organization_id: nil}), do: {:error, "Account is not an organization."}

  defp organization_for_account(account) do
    case Accounts.get_organization_by_id(account.organization_id) do
      {:ok, organization} -> {:ok, organization}
      _ -> {:error, "Organization not found."}
    end
  end

  defp members(organization, page, page_size) do
    {members, total_count} =
      Accounts.list_organization_members_with_role(organization, page: page, page_size: page_size)

    {Enum.map(members, fn [member, role] ->
       %{id: member.id, email: member.email, name: member.account.name, role: role}
     end), total_count}
  end

  defp invitations(organization, account, assigns, page, page_size) do
    case MCPTool.authorize_account(assigns, account, :read, :invitation) do
      {:ok, _account} ->
        {invitations, total_count} =
          Accounts.list_organization_invitations(organization, page: page, page_size: page_size)

        {Enum.map(invitations, fn invitation ->
           %{
             id: invitation.id,
             invitee_email: invitation.invitee_email,
             role: invitation.role,
             expired: Accounts.invitation_expired?(invitation)
           }
         end), total_count}

      {:error, _message} ->
        {[], 0}
    end
  end

  defp pagination_metadata(total_count, page, page_size) do
    total_pages = ceil(total_count / page_size)

    MCPTool.pagination_metadata(%{
      has_next_page?: page < total_pages,
      has_previous_page?: page > 1,
      total_count: total_count,
      total_pages: total_pages,
      current_page: page,
      page_size: page_size
    })
  end
end
