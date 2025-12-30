defmodule TuistWeb.API.InvitationsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts
  alias Tuist.Authorization
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.Invitation
  alias TuistWeb.Authentication

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_message: TuistWeb.RenderAPIErrorPlug
  )

  tags ["Invitations"]

  operation(:create,
    summary: "Creates an invitation",
    description: "Invites a user with a given email to a given organization.",
    operation_id: "createInvitation",
    parameters: [
      organization_name: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the organization."
      ]
    ],
    request_body:
      {"Invitation params", "application/json",
       %Schema{
         type: :object,
         properties: %{
           invitee_email: %Schema{
             type: :string,
             description: "The email of the invitee."
           }
         },
         required: [:invitee_email]
       }},
    responses: %{
      ok: {"The user was invited", "application/json", Invitation},
      bad_request: {"The user could not be invited due to a validation error", "application/json", Error},
      not_found: {"The organization was not found", "application/json", Error},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error}
    }
  )

  def create(
        %{path_params: %{"organization_name" => organization_name}, body_params: %{invitee_email: invitee_email}} = conn,
        _params
      ) do
    user = Authentication.current_user(conn)
    user_account = Accounts.get_account_from_user(user)

    organization = Accounts.get_organization_by_handle(organization_name)

    invitee_email_valid? = Tuist.Accounts.User.email_valid?(invitee_email)

    invitee =
      case Accounts.get_user_by_email(invitee_email) do
        {:ok, user} -> user
        {:error, :not_found} -> nil
      end

    cond do
      is_nil(organization) ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Organization #{organization_name} was not found."})

      Authorization.authorize(:invitation_create, user, organization.account) != :ok ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "The authenticated subject is not authorized to perform this action"})

      !is_nil(
        Accounts.get_invitation_by_invitee_email_and_organization(
          invitee_email,
          organization
        )
      ) ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "The user is already invited to the organization."})

      !is_nil(invitee) and
          (Accounts.organization_admin?(invitee, organization) or
             Accounts.organization_user?(invitee, organization)) ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "The user is already a member of the organization."})

      not invitee_email_valid? ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "The invitee email address is not a valid email address."})

      !is_nil(organization) ->
        {:ok, invitation} =
          Accounts.invite_user_to_organization(invitee_email, %{
            inviter: user,
            to: organization,
            url: &url(~p"/auth/invitations/#{&1}")
          })

        conn
        |> put_status(:ok)
        |> json(%{
          id: invitation.id,
          invitee_email: invitation.invitee_email,
          inviter: %{
            id: user.id,
            email: user.email,
            name: user_account.name
          },
          token: invitation.token,
          organization_id: invitation.organization_id
        })
    end
  end

  operation(:delete,
    summary: "Cancels an invitation",
    description: "Cancels an invitation for a given invitee email and an organization.",
    operation_id: "cancelInvitation",
    parameters: [
      organization_name: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the organization."
      ]
    ],
    request_body:
      {"Invitation params", "application/json",
       %Schema{
         type: :object,
         properties: %{
           invitee_email: %Schema{
             type: :string,
             description: "The email of the invitee."
           }
         },
         required: [:invitee_email]
       }},
    responses: %{
      no_content: "The invitation was cancelled",
      not_found:
        {"The invitation with the given invitee email and organization name was not found", "application/json", Error},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error}
    }
  )

  def delete(
        %{path_params: %{"organization_name" => organization_name}, body_params: %{invitee_email: invitee_email}} = conn,
        _params
      ) do
    user = Authentication.current_user(conn)

    organization = Accounts.get_organization_by_handle(organization_name)

    invitation =
      if is_nil(organization) do
        nil
      else
        Accounts.get_invitation_by_invitee_email_and_organization(
          invitee_email,
          organization
        )
      end

    cond do
      is_nil(invitation) ->
        conn
        |> put_status(:not_found)
        |> json(%{
          message: "The invitation with the given invitee email and organization name was not found"
        })

      Authorization.authorize(:invitation_delete, user, organization.account) != :ok ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "The authenticated subject is not authorized to perform this action"})

      true ->
        Accounts.cancel_invitation(invitation)

        conn
        |> put_status(:no_content)
        |> json(%{})
    end
  end
end
