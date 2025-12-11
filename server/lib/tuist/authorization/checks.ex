defmodule Tuist.Authorization.Checks do
  @moduledoc ~S"""
  This module contains check functions for the authorization of users and projects.
  """
  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Projects.Project

  @scope_groups %{
    "ci" => [
      "project:cache:write",
      "project:previews:write",
      "project:bundles:write",
      "project:tests:write",
      "project:builds:write",
      "project:runs:write"
    ]
  }

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

  @doc """
  Checks if the authenticated account's scopes include the required scope.

  Scopes are expected to be strings in the format "entity:object:action"
  (e.g., "project:cache:read", "account:registry:read").

  Scope groups (e.g., "ci") are automatically expanded to their component scopes.

  When the object is a Project, this also verifies the token has access to that
  specific project (either via `all_projects: true` or the project being in `project_ids`).
  """
  def scopes_permit(%AuthenticatedAccount{scopes: scopes} = auth_account, %Project{} = project, scope)
      when is_binary(scope) do
    expanded_scopes = expand_scope_groups(scopes)
    Enum.member?(expanded_scopes, scope) and project_access_permitted(auth_account, project)
  end

  def scopes_permit(%AuthenticatedAccount{scopes: scopes}, _, scope) when is_binary(scope) do
    expanded_scopes = expand_scope_groups(scopes)
    Enum.member?(expanded_scopes, scope)
  end

  def scopes_permit(_, _, _) do
    false
  end

  defp expand_scope_groups(scopes) do
    Enum.flat_map(scopes, fn scope ->
      Map.get(@scope_groups, scope, [scope])
    end)
  end

  @doc """
  Checks if the authenticated account has access to the specified project.

  When `all_projects` is true, the token has access to all projects under the account.
  When `all_projects` is false, access is restricted to projects in `project_ids`.
  """
  def project_access_permitted(%AuthenticatedAccount{all_projects: true}, _project) do
    true
  end

  def project_access_permitted(%AuthenticatedAccount{all_projects: false, project_ids: nil}, _project) do
    false
  end

  def project_access_permitted(%AuthenticatedAccount{all_projects: false, project_ids: []}, _project) do
    false
  end

  def project_access_permitted(%AuthenticatedAccount{all_projects: false, project_ids: project_ids}, %Project{
        id: project_id
      }) do
    project_id in project_ids
  end

  def project_access_permitted(_, _) do
    true
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

  def ops_access(_, _) do
    false
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
