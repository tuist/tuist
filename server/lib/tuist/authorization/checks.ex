defmodule Tuist.Authorization.Checks do
  @moduledoc ~S"""
  This module contains check functions for the authorization of users and projects.
  """
  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Projects.Project

  def user_role(%User{} = authenticated_user, %Project{} = project, role) when role == :user do
    Accounts.owns_account_or_belongs_to_account_organization?(authenticated_user, %{
      id: project.account_id
    })
  end

  def user_role(%User{} = authenticated_user, %Project{} = project, role) when role == :admin do
    Accounts.owns_account_or_is_admin_to_account_organization?(authenticated_user, %{
      id: project.account_id
    })
  end

  def user_role(%User{} = authenticated_user, %Account{} = account, role) when role == :user do
    Accounts.owns_account_or_belongs_to_account_organization?(authenticated_user, %{
      id: account.id
    })
  end

  def user_role(%User{} = authenticated_user, %Account{} = account, role) when role == :admin do
    Accounts.owns_account_or_is_admin_to_account_organization?(authenticated_user, %{
      id: account.id
    })
  end

  def user_role(_, _, _) do
    false
  end

  def authenticated_as_user(%User{}, _) do
    true
  end

  def authenticated_as_user(_, _) do
    false
  end

  def authenticated_as_project(%Project{}, _) do
    true
  end

  def authenticated_as_project(_, _) do
    false
  end

  def authenticated_as_account(%AuthenticatedAccount{}, _) do
    true
  end

  def authenticated_as_account(_, _) do
    false
  end

  def accounts_match(%AuthenticatedAccount{account: %Account{} = authenticated_account}, %Account{} = account) do
    authenticated_account.id == account.id
  end

  def accounts_match(%Project{account: %Account{} = project_account}, %Account{} = account) do
    project_account.id == account.id
  end

  def accounts_match(_, _) do
    false
  end

  def scopes_permit(%AuthenticatedAccount{scopes: scopes}, _, scope) do
    Enum.member?(scopes, scope)
  end

  def scopes_permit(_, _, _) do
    false
  end

  def projects_match(%User{}, %Project{}) do
    false
  end

  def projects_match(%Project{} = authenticated_project, %Project{} = project) do
    authenticated_project.id == project.id
  end

  def projects_match(_, _) do
    false
  end

  def public_project(_, %Project{visibility: :public}) do
    true
  end

  def public_project(_, %Project{visibility: :private}) do
    false
  end

  def public_project(_, %Project{}) do
    false
  end

  def billing_access(%User{} = user, %Account{} = account) do
    subscription = Tuist.Billing.get_current_active_subscription(account)

    if not Tuist.Environment.tuist_hosted?() or
         (not is_nil(subscription) and subscription.plan == :open_source) do
      false
    else
      Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
    end
  end

  def ops_access(%User{} = user, _) do
    if Tuist.Environment.dev?() do
      true
    else
      user.account.name in Tuist.Environment.ops_user_handles()
    end
  end

  def repository_permission_check(%User{} = user, %{project: %Project{} = project, repository: repository}) do
    account = Accounts.get_account_by_id(project.account_id)

    if Accounts.owns_account_or_is_admin_to_account_organization?(user, account) do
      case Tuist.VCS.get_user_permission(%{user: user, repository: repository}) do
        {:ok, %Tuist.VCS.Repositories.Permission{permission: permission}} ->
          Enum.member?(["admin", "write"], permission)

        _ ->
          false
      end
    else
      false
    end
  end

  def project_command_event_access(%User{} = user, %{project: %Project{} = project}) do
    user_role(user, project, :user)
  end

  def project_command_event_access(%User{} = user, command_event) when is_struct(command_event) do
    case Map.get(command_event, :project) do
      %Project{} = project ->
        user_role(user, project, :user)

      _ ->
        case Map.get(command_event, :project_id) do
          project_id when not is_nil(project_id) ->
            project = Tuist.Projects.get_project_by_id(project_id)
            user_role(user, project, :user)

          _ ->
            false
        end
    end
  end

  def project_command_event_access(nil, command_event) when is_struct(command_event) do
    case Map.get(command_event, :project) do
      %Project{} = project ->
        public_project(nil, project)

      _ ->
        case Map.get(command_event, :project_id) do
          project_id when not is_nil(project_id) ->
            project = Tuist.Projects.get_project_by_id(project_id)
            public_project(nil, project)

          _ ->
            false
        end
    end
  end

  def project_command_event_access(_, _) do
    false
  end

  def command_event_project_access(user_or_nil, command_event) when is_struct(command_event) do
    project =
      case Map.get(command_event, :project) do
        %Project{} = project ->
          project

        _ ->
          case Map.get(command_event, :project_id) do
            project_id when not is_nil(project_id) ->
              Tuist.Projects.get_project_by_id(project_id)

            _ ->
              nil
          end
      end

    case project do
      %Project{} = project ->
        if public_project(user_or_nil, project) do
          true
        else
          case user_or_nil do
            %User{} = user ->
              user_role(user, project, :user)

            _ ->
              false
          end
        end

      _ ->
        false
    end
  end

  def command_event_project_access(_, _) do
    false
  end
end
