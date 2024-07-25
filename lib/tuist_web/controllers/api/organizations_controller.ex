defmodule TuistWeb.API.OrganizationsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller
  alias Tuist.Billing
  alias TuistWeb.API.Schemas.OrganizationMember
  alias TuistWeb.Authentication
  alias Tuist.Authorization
  alias Tuist.Accounts
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.{Error, Organization, OrganizationUsage}

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_message: TuistWeb.RenderAPIErrorPlug
  )

  tags ["Organizations"]

  operation(:index,
    summary: "Lists the organizations",
    description: "Returns all the organizations the authenticated subject is part of.",
    parameters: [],
    operation_id: "listOrganizations",
    responses: %{
      ok:
        {"The list of organizations", "application/json",
         %Schema{
           title: "OrganizationList",
           description: "The list of organizations the authenticated subject is part of.",
           type: :object,
           properties: %{
             organizations: %Schema{
               type: :array,
               items: Organization
             }
           },
           required: [:organizations]
         }},
      unauthorized:
        {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error}
    }
  )

  def index(conn, _params) do
    organizations =
      TuistWeb.Authentication.current_user(conn)
      |> Tuist.Accounts.get_user_organization_accounts()
      |> Enum.map(
        &%{
          id: &1.organization.id,
          name: &1.account.name,
          plan: get_plan(&1.account),
          # We don't display in the CLI members and invitations when showing a list of organizations.
          # We keep these fields for backwards compatibility but should remove in the future.
          members: [],
          invitations: []
        }
      )

    conn |> json(%{organizations: organizations})
  end

  defp get_plan(account) do
    Billing.get_current_active_subscription(account)
    |> case do
      %Billing.Subscription{} = subscription -> subscription.plan
      nil -> :none
    end
  end

  operation(:create,
    summary: "Creates an organization",
    description: "Creates an organization with the given name.",
    operation_id: "createOrganization",
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
        organization =
          Accounts.create_organization(%{name: organization_name, creator: user})

        organization_account = Accounts.get_account_from_organization(organization)

        conn
        |> put_status(:ok)
        |> json(%{
          id: organization.id,
          name: organization_name,
          plan: get_plan(organization_account),
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
    operation_id: "deleteOrganization",
    parameters: [
      organization_name: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the organization to delete."
      ]
    ],
    responses: %{
      no_content: "The organization was deleted",
      not_found:
        {"The organization with the given name was not found", "application/json", Error},
      unauthorized:
        {"You need to be authenticated to access this resource", "application/json", Error},
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
    operation_id: "showOrganization",
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
      unauthorized:
        {"You need to be authenticated to access this resource", "application/json", Error},
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

        admin_ids = Enum.map(admins, & &1.id)

        users =
          Accounts.get_organization_members(organization_account.organization, :user)
          |> Enum.filter(fn member ->
            member.id not in admin_ids
          end)
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
          plan: get_plan(organization_account.account),
          members: admins ++ users,
          sso_provider: organization_account.organization.sso_provider,
          sso_organization_id: organization_account.organization.sso_organization_id,
          invitations:
            Tuist.Repo.preload(organization_account.organization,
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

  operation(:usage,
    summary: "Shows the usage of an organization",
    description:
      "Returns the usage of the organization with the given identifier. (e.g. number of remote cache hits)",
    operation_id: "showOrganizationUsage",
    parameters: [
      organization_name: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the organization to show."
      ]
    ],
    responses: %{
      ok: {"The organization usage", "application/json", OrganizationUsage},
      not_found:
        {"The organization with the given name was not found", "application/json", Error},
      unauthorized:
        {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error}
    }
  )

  def usage(
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

      !Authorization.can(user, :read, organization_account.account, :organization_usage) ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "The authenticated subject is not authorized to perform this action"})

      !is_nil(organization_account) ->
        conn
        |> json(%{
          current_month_remote_cache_hits:
            organization_account.account.current_month_remote_cache_hits_count
        })
    end
  end

  operation(:update,
    summary: "Updates an organization",
    description: "Updates an organization with given parameters.",
    operation_id: "updateOrganization",
    parameters: [
      organization_name: [
        in: :path,
        type: :string,
        required: true,
        description: "The name of the organization to update."
      ]
    ],
    request_body:
      {"Organization update params", "application/json",
       %Schema{
         type: :object,
         properties: %{
           sso_provider: %Schema{
             type: :string,
             enum: ["google", "none"],
             description: "The SSO provider to set up for the organization"
           },
           sso_organization_id: %Schema{
             type: :string,
             description: "The SSO organization ID to be associated with the SSO provider",
             nullable: true
           }
         }
       }},
    responses: %{
      ok: {"The organization", "application/json", Organization},
      not_found:
        {"The organization with the given name was not found", "application/json", Error},
      bad_request:
        {"The organization could not be updated due to a validation error", "application/json",
         Error},
      unauthorized:
        {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error}
    }
  )

  def update(
        %{
          path_params: %{
            "organization_name" => organization_name
          },
          body_params:
            %{
              sso_provider: sso_provider
            } = body_params
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
        |> json(%{message: "Organization #{organization_name} was not found."})

      !Authorization.can(user, :update, organization_account.account, :organization) ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "The authenticated subject is not authorized to perform this action."})

      sso_provider == "none" ->
        {:ok, organization} =
          Accounts.update_organization(organization_account.organization, %{
            sso_provider: nil,
            sso_organization_id: nil
          })

        conn
        |> json(%{
          id: organization.id,
          name: organization_name,
          plan: get_plan(organization_account.account),
          sso_provider: organization.sso_provider,
          sso_organization_id: organization.sso_organization_id,
          members: [],
          invitations: []
        })

      is_nil(
        Accounts.find_oauth2_identity(%{user: user, provider: String.to_atom(sso_provider)},
          provider_organization_id: body_params.sso_organization_id
        )
      ) ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          message:
            "Your SSO organization must be the same as the one you are trying to update your organization to."
        })

      !is_nil(organization_account) ->
        update_organization(%{
          organization_account: organization_account,
          sso_provider: sso_provider,
          sso_organization_id: body_params.sso_organization_id,
          conn: conn
        })
    end
  end

  defp update_organization(%{
         organization_account: organization_account,
         sso_provider: sso_provider,
         sso_organization_id: sso_organization_id,
         conn: %Plug.Conn{} = conn
       }) do
    organization = organization_account.organization

    case Accounts.update_organization(organization, %{
           sso_provider: String.to_atom(sso_provider),
           sso_organization_id: sso_organization_id
         }) do
      {:ok, organization} ->
        conn
        |> json(%{
          id: organization.id,
          name: organization_account.account.name,
          plan: get_plan(organization_account.account),
          sso_provider: organization.sso_provider,
          sso_organization_id: organization.sso_organization_id,
          members: [],
          invitations: []
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        message =
          Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
          |> Enum.flat_map(fn {_key, value} -> value end)
          |> hd

        conn
        |> put_status(:bad_request)
        |> json(%Error{message: message})
    end
  end

  operation(:remove_member,
    summary: "Removes a member from an organization",
    description: "Removes a member with a given username from a given organization",
    operation_id: "removeOrganizationMember",
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
      unauthorized:
        {"You need to be authenticated to access this resource", "application/json", Error},
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

      is_nil(member_account) or is_nil(member_account.user_id) ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "User #{user_name} not found."})

      !Authorization.can(user, :delete, organization_account.account, :member) ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "The authenticated subject is not authorized to perform this action"})

      true ->
        member = Accounts.get_user_by_id(member_account.user_id)
        organization = organization_account.organization

        cond do
          Accounts.belongs_to_sso_organization?(member, organization) ->
            Accounts.delete_user(member)

            conn
            |> put_status(:no_content)
            |> json(%{})

          Accounts.belongs_to_organization?(member, organization_account.organization) ->
            Accounts.remove_user_from_organization(member, organization)

            conn
            |> put_status(:no_content)
            |> json(%{})

          true ->
            conn
            |> put_status(:bad_request)
            |> json(%{
              message:
                "User #{user_name} is not a member of the organization #{organization_name}"
            })
        end
    end
  end

  operation(:update_member,
    summary: "Updates a member in an organization",
    description: "Updates a member in a given organization",
    operation_id: "updateOrganizationMember",
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
      unauthorized:
        {"You need to be authenticated to access this resource", "application/json", Error},
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

      is_nil(member_account) or is_nil(member_account.user_id) ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "User #{user_name} not found."})

      !Authorization.can(user, :update, organization_account.account, :member) ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "The authenticated subject is not authorized to perform this action"})

      true ->
        member = Accounts.get_user_by_id(member_account.user_id)
        member_account = Accounts.get_account_from_user(member)
        organization = organization_account.organization

        current_user_role = Accounts.get_user_role_in_organization(member, organization)

        if is_nil(current_user_role) and
             Accounts.belongs_to_sso_organization?(member, organization_account.organization) do
          Accounts.add_user_to_organization(member, organization_account.organization,
            role: String.to_atom(role)
          )
        end

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
