defmodule TuistCloudWeb.API.OrganizationsController do
  use OpenApiSpex.ControllerSpecs
  use TuistCloudWeb, :controller
  alias TuistCloudWeb.API.Schemas.OrganizationMember
  alias TuistCloudWeb.Authentication
  alias TuistCloud.Authorization
  alias TuistCloud.Accounts
  alias OpenApiSpex.Schema
  alias TuistCloudWeb.API.Schemas.{Error, Organization}

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_message: TuistCloudWeb.RenderAPIErrorPlug
  )

  operation(:index,
    summary: "Lists the organizations",
    description: "Returns all the organizations the authenticated subject is part of.",
    parameters: [],
    responses: %{
      ok:
        {"The list of organizations", "application/json",
         %Schema{
           title: "Organization list",
           description: "The list of organizations the authenticated subject is part of.",
           type: :array,
           items: %Schema{
             type: :string
           }
         }},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error}
    }
  )

  def index(conn, _params) do
    organizations =
      TuistCloudWeb.Authentication.current_user(conn)
      |> TuistCloud.Accounts.get_user_organization_accounts()
      |> Enum.map(
        &%{
          id: &1.organization.id,
          name: &1.account.name,
          plan: &1.account.plan,
          # We don't display in the CLI members and invitations when showing a list of organizations.
          # We keep these fields for backwards compatibility but should remove in the future.
          members: [],
          invitations: []
        }
      )

    conn |> json(%{organizations: organizations})
  end

  operation(:create,
    summary: "Creates an organization",
    description: "Creates an organization with the given name.",
    request_body:
      {"Organization params", "application/json",
       %Schema{
         type: :object,
         properties: %{
           name: %Schema{
             type: :string,
             description: "The name of the organization that should be created."
           }
         },
         required: [:name]
       }},
    responses: %{
      ok: {"The organization was created", "application/json", Organization},
      bad_request:
        {"The organization could not be created due to a validation error", "application/json",
         Error}
    }
  )

  def create(
        %{
          body_params: %{
            name: organization_name
          }
        } = conn,
        _params
      ) do
    user = Authentication.current_user(conn)
    existing_organization = Accounts.get_organization_account_by_name(organization_name)

    cond do
      String.contains?(organization_name, ".") ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          message:
            "Organization name can't contain a dot. Please use a different name, such as #{String.replace(organization_name, ".", "-")}."
        })

      is_nil(existing_organization) ->
        organization = Accounts.create_organization(%{name: organization_name, creator: user})
        organization_account = Accounts.get_account_from_organization(organization)

        conn
        |> put_status(:ok)
        |> json(%{
          id: organization.id,
          name: organization_name,
          plan: organization_account.plan,
          members: [],
          invitations: []
        })

      !is_nil(existing_organization) ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "Organization #{organization_name} already exists"})
    end
  end

  operation(:delete,
    summary: "Deletes an organization",
    description: "Deletes the organization with the given name.",
    parameters: [
      organization_name: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the organization to delete."
      ]
    ],
    responses: %{
      no_content: {"The organization was deleted", "application/json", nil},
      not_found:
        {"The organization with the given name was not found", "application/json", Error},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error}
    }
  )

  def delete(
        %{
          path_params: %{
            "organization_name" => organization_name
          }
        } = conn,
        _params
      ) do
    organization_account = Accounts.get_organization_account_by_name(organization_name)

    user = Authentication.current_user(conn)

    cond do
      is_nil(organization_account) ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Organization #{organization_name} not found."})

      !Authorization.can(user, :delete, organization_account.account, :organization) ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "The authenticated subject is not authorized to perform this action"})

      !is_nil(organization_account) ->
        organization = organization_account.organization
        Accounts.delete_organization(organization)

        conn
        |> put_status(:no_content)
        |> json(%{})
    end
  end

  operation(:show,
    summary: "Shows an organization",
    description: "Returns the organization with the given identifier.",
    parameters: [
      organization_name: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the organization to show."
      ]
    ],
    responses: %{
      ok: {"The organization", "application/json", Organization},
      not_found:
        {"The organization with the given name was not found", "application/json", Error},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error}
    }
  )

  def show(
        %{
          path_params: %{
            "organization_name" => organization_name
          }
        } = conn,
        _params
      ) do
    organization_account =
      Accounts.get_organization_account_by_name(organization_name)

    user = Authentication.current_user(conn)

    cond do
      is_nil(organization_account) ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Organization not found"})

      !Authorization.can(user, :read, organization_account.account, :organization) ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "The authenticated subject is not authorized to perform this action"})

      !is_nil(organization_account) ->
        admins =
          Accounts.get_organization_members(organization_account.organization, :admin)
          |> Enum.map(
            &%{
              id: &1.id,
              email: &1.email,
              name: &1.account.name,
              role: "admin"
            }
          )

        users =
          Accounts.get_organization_members(organization_account.organization, :user)
          |> Enum.map(
            &%{
              id: &1.id,
              email: &1.email,
              name: &1.account.name,
              role: "user"
            }
          )

        conn
        |> json(%{
          id: organization_account.organization.id,
          name: organization_name,
          plan: organization_account.account.plan,
          members: admins ++ users,
          invitations:
            TuistCloud.Repo.preload(organization_account.organization,
              invitations: [inviter: :account]
            ).invitations
            |> Enum.map(
              &%{
                id: &1.id,
                invitee_email: &1.invitee_email,
                inviter: %{
                  id: &1.inviter.id,
                  email: &1.inviter.email,
                  name: &1.inviter.account.name
                },
                token: &1.token,
                organization_id: &1.organization_id
              }
            )
        })
    end
  end

  operation(:remove_member,
    summary: "Removes a member from an organization",
    description: "Removes a member with a given username from a given organization",
    parameters: [
      organization_name: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the organization to remove the member from."
      ],
      user_name: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the user to remove from the organization."
      ]
    ],
    responses: %{
      no_content: {"The member was removed", "application/json", nil},
      not_found:
        {"The organization or the user with the given name was not found", "application/json",
         Error},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      bad_request:
        {"The member could not be removed due to a validation error", "application/json", Error}
    }
  )

  def remove_member(
        %{
          path_params: %{
            "organization_name" => organization_name,
            "user_name" => user_name
          }
        } = conn,
        _params
      ) do
    organization_account = Accounts.get_organization_account_by_name(organization_name)
    user = Authentication.current_user(conn)
    member_account = Accounts.get_account_by_handle(user_name)

    cond do
      is_nil(organization_account) ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Organization #{organization_name} not found."})

      is_nil(member_account) or member_account.owner_type != "User" ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "User #{user_name} not found."})

      !Authorization.can(user, :delete, organization_account.account, :member) ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "The authenticated subject is not authorized to perform this action"})

      true ->
        member = Accounts.get_user_by_id(member_account.owner_id)
        organization = organization_account.organization

        if Accounts.belongs_to_organization?(member, organization_account.organization) do
          Accounts.remove_user_from_organization(member, organization)

          conn
          |> put_status(:no_content)
          |> json(%{})
        else
          conn
          |> put_status(:bad_request)
          |> json(%{
            message: "User #{user_name} is not a member of the organization #{organization_name}"
          })
        end
    end
  end

  operation(:update_member,
    summary: "Updates a member in an organization",
    description: "Updates a member in a given organization",
    parameters: [
      organization_name: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the organization to update the member in."
      ],
      user_name: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the user to update in the organization."
      ]
    ],
    request_body:
      {"Member update params", "application/json",
       %Schema{
         type: :object,
         properties: %{
           role: %Schema{
             type: :string,
             enum: ["admin", "user"],
             description: "The role to update the member to"
           }
         },
         required: [:role]
       }},
    responses: %{
      ok: {"The member was updated", "application/json", OrganizationMember},
      not_found:
        {"The organization or the user with the given name was not found", "application/json",
         Error},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      bad_request:
        {"The member could not be updated due to a validation error", "application/json", Error}
    }
  )

  def update_member(
        %{
          path_params: %{
            "organization_name" => organization_name,
            "user_name" => user_name
          },
          body_params: %{
            role: role
          }
        } = conn,
        _params
      ) do
    organization_account = Accounts.get_organization_account_by_name(organization_name)

    user = Authentication.current_user(conn)

    member_account = Accounts.get_account_by_handle(user_name)

    cond do
      is_nil(organization_account) ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Organization #{organization_name} not found."})

      is_nil(member_account) or member_account.owner_type != "User" ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "User #{user_name} not found."})

      !Authorization.can(user, :update, organization_account.account, :member) ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "The authenticated subject is not authorized to perform this action"})

      true ->
        member = Accounts.get_user_by_id(member_account.owner_id)
        member_account = Accounts.get_account_from_user(member)
        organization = organization_account.organization

        if Accounts.belongs_to_organization?(member, organization) do
          Accounts.update_user_role_in_organization(member, organization, String.to_atom(role))

          conn
          |> json(%{
            id: member.id,
            email: member.email,
            name: member_account.name,
            role: role
          })
        else
          conn
          |> put_status(:bad_request)
          |> json(%{
            message: "User #{user_name} is not a member of the organization #{organization_name}"
          })
        end
    end
  end
end
