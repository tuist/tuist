defmodule Tuist.MCP.Components.Tools.OrganizationInvitationTools do
  @moduledoc false

  alias Tuist.Accounts
  alias Tuist.Authorization

  def authorize_organization(user, organization_handle, action) do
    organization_account =
      user
      |> Accounts.get_user_organization_accounts()
      |> Enum.find(&(&1.account.name == organization_handle))

    if not is_nil(organization_account) and Authorization.authorize(action, user, organization_account.account) == :ok do
      {:ok, organization_account}
    else
      {:error, "The authenticated subject is not authorized to perform this action."}
    end
  end

  def normalize_email(email), do: email |> String.trim() |> String.downcase()
end

defmodule Tuist.MCP.Components.Tools.InviteOrganizationMember do
  @moduledoc """
  Invite someone to an organization by email.
  """

  use Tuist.MCP.Tool,
    name: "invite_organization_member",
    title: "Invite Organization Member",
    read_only_hint: false,
    open_world_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "organization_handle" => %{
          "type" => "string",
          "description" => "The organization handle."
        },
        "email" => %{
          "type" => "string",
          "description" => "The email address to invite. It does not need to belong to an existing Tuist user."
        },
        "role" => %{
          "type" => "string",
          "enum" => ["user", "admin", "viewer"],
          "description" =>
            "The role the invitee gets when they accept the invitation. Defaults to user. `viewer` is read-only."
        }
      },
      "required" => ["organization_handle", "email"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "integer"},
        "invitee_email" => %{"type" => "string"},
        "organization_handle" => %{"type" => "string"},
        "role" => %{"type" => "string", "enum" => ["user", "admin", "viewer"]},
        "expires_at" => %{"type" => "string"},
        "email_sent" => %{"type" => "boolean"}
      },
      "required" => ["id", "invitee_email", "organization_handle", "role", "expires_at", "email_sent"],
      "additionalProperties" => false
    }

  alias Tuist.Accounts
  alias Tuist.Accounts.Invitation
  alias Tuist.Accounts.User
  alias Tuist.Environment
  alias Tuist.MCP.Components.Tools.OrganizationInvitationTools
  alias Tuist.MCP.Formatter

  @impl EMCP.Tool
  def description do
    "Invite someone to an organization by email, whether or not they already have a Tuist account. Tuist emails them a link to accept the invitation, which expires after #{Invitation.validity_days()} days. When `email_sent` is false, the server cannot send email and the invitation link must be copied from the organization's Members page in the dashboard. Invitation acceptance tokens are never returned."
  end

  def execute(%{assigns: %{current_user: user}}, %{"organization_handle" => organization_handle, "email" => email} = args)
      when is_binary(organization_handle) and is_binary(email) do
    email = OrganizationInvitationTools.normalize_email(email)
    role = Map.get(args, "role", "user")

    with {:ok, %{organization: organization, account: account}} <-
           OrganizationInvitationTools.authorize_organization(user, organization_handle, :invitation_create),
         :ok <- validate_invitee(email, organization) do
      invite(user, organization, account, email, role)
    end
  end

  def execute(_conn, _args), do: {:error, "You must authenticate as a user to invite organization members."}

  defp validate_invitee(email, organization) do
    cond do
      not User.email_valid?(email) ->
        {:error, "#{email} is not a valid email address."}

      not is_nil(Accounts.get_invitation_by_invitee_email_and_organization(email, organization)) ->
        {:error, "#{email} is already invited to the organization."}

      member?(email, organization) ->
        {:error, "#{email} is already a member of the organization."}

      true ->
        :ok
    end
  end

  defp member?(email, organization) do
    case Accounts.get_user_by_email(email) do
      {:ok, invitee} -> Accounts.belongs_to_organization?(invitee, organization)
      {:error, :not_found} -> false
    end
  end

  defp invite(user, organization, account, email, role) do
    case Accounts.invite_user_to_organization(
           email,
           %{
             inviter: user,
             to: organization,
             url: &Environment.app_url(path: "/auth/invitations/#{&1}")
           },
           role: String.to_existing_atom(role)
         ) do
      {:ok, invitation} ->
        {:ok,
         %{
           id: invitation.id,
           invitee_email: invitation.invitee_email,
           organization_handle: account.name,
           role: invitation.role,
           expires_at: Formatter.iso8601(Invitation.expires_at(invitation), naive: :utc),
           email_sent: Environment.mail_configured?()
         }}

      {:error, changeset} ->
        {:error, Formatter.changeset_errors(changeset)}
    end
  end
end

defmodule Tuist.MCP.Components.Tools.CancelOrganizationInvitation do
  @moduledoc """
  Cancel a pending organization invitation.
  """

  use Tuist.MCP.Tool,
    name: "cancel_organization_invitation",
    title: "Cancel Organization Invitation",
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
          "description" => "The email address the invitation was sent to."
        }
      },
      "required" => ["organization_handle", "email"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "invitee_email" => %{"type" => "string"},
        "organization_handle" => %{"type" => "string"}
      },
      "required" => ["invitee_email", "organization_handle"],
      "additionalProperties" => false
    }

  alias Tuist.Accounts
  alias Tuist.MCP.Components.Tools.OrganizationInvitationTools

  @impl EMCP.Tool
  def description, do: "Cancel a pending organization invitation so its link can no longer be accepted."

  def execute(%{assigns: %{current_user: user}}, %{"organization_handle" => organization_handle, "email" => email})
      when is_binary(organization_handle) and is_binary(email) do
    email = OrganizationInvitationTools.normalize_email(email)

    with {:ok, %{organization: organization, account: account}} <-
           OrganizationInvitationTools.authorize_organization(user, organization_handle, :invitation_delete) do
      case Accounts.get_invitation_by_invitee_email_and_organization(email, organization) do
        nil ->
          {:error, "No pending invitation for #{email} was found in the organization."}

        invitation ->
          :ok = Accounts.cancel_invitation(invitation)
          {:ok, %{invitee_email: invitation.invitee_email, organization_handle: account.name}}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "You must authenticate as a user to cancel organization invitations."}
end
