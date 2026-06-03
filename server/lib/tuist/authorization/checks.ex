defmodule Tuist.Authorization.Checks do
  @moduledoc ~S"""
  This module contains check functions for the authorization of users and projects.
  """
  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.AuthenticatedService
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
    ],
    "mcp" => [
      "project:admin:read",
      "project:cache:read",
      "project:previews:read",
      "project:bundles:read",
      "project:tests:read",
      "project:builds:read",
      "project:runs:read"
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

  def authenticated_as_service(%AuthenticatedService{}, _) do
    true
  end

  def authenticated_as_service(_, _) do
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
  (e.g., "project:cache:read", "account:members:read").

  Scope groups (e.g., "ci") are automatically expanded to their component scopes.

  When the object is a Project, this also verifies the token has access to that
  specific project (either via `all_projects: true` or the project being in `project_ids`).
  """
  def scopes_permit(%AuthenticatedAccount{scopes: scopes} = auth_account, %Project{} = project, scope)
      when is_binary(scope) do
    expanded_scopes = expand_scopes(scopes)
    Enum.member?(expanded_scopes, scope) and project_access_permitted(auth_account, project)
  end

  def scopes_permit(%AuthenticatedAccount{scopes: scopes}, _, scope) when is_binary(scope) do
    expanded_scopes = expand_scopes(scopes)
    Enum.member?(expanded_scopes, scope)
  end

  # Service subjects are not tied to an account, so this check intentionally has
  # no per-tenant binding: holding the scope grants it across every account and
  # project. Only wire this into policies with explicitly cross-tenant scopes
  # (e.g. "account:service:*:any"), never with tenant-scoped project/account
  # scopes that are meant to be bound to the subject's own account.
  def scopes_permit(%AuthenticatedService{scopes: scopes}, _, scope) when is_binary(scope) do
    expanded_scopes = expand_scopes(scopes)
    Enum.member?(expanded_scopes, scope)
  end

  def scopes_permit(_, _, _) do
    false
  end

  def expand_scopes(scopes) do
    Enum.flat_map(scopes, fn scope ->
      Map.get(@scope_groups, scope, [scope])
    end)
  end

  @doc """
  Checks if the authenticated account has access to the specified project.

  When `all_projects` is true, the token has access to all projects under the account.
  When `all_projects` is false, access is restricted to projects in `project_ids`.
  """
  def project_access_permitted(%AuthenticatedAccount{issued_by: %User{} = user, all_projects: true}, %Project{} = project) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, %{id: project.account_id})
  end

  def project_access_permitted(%AuthenticatedAccount{account: %Account{id: account_id}, all_projects: true}, %Project{
        account_id: project_account_id
      }) do
    account_id == project_account_id
  end

  def project_access_permitted(%AuthenticatedAccount{all_projects: false, project_ids: nil}, _project) do
    false
  end

  def project_access_permitted(%AuthenticatedAccount{all_projects: false, project_ids: []}, _project) do
    false
  end

  def project_access_permitted(
        %AuthenticatedAccount{account: %Account{id: account_id}, all_projects: false, project_ids: project_ids},
        %Project{id: project_id, account_id: project_account_id}
      ) do
    account_id == project_account_id and project_id in project_ids
  end

  def project_access_permitted(_, _) do
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

  @doc """
  Gates the INTERNAL ops admin panel (`/ops`, the `:ops` policy
  object). Unlike `ops_access/2` this is not tied to a customer
  account and is not grant-based — it's the "is this person Tuist
  staff" check. The object is ignored (the panel passes `nil`/`:ops`).
  """
  def internal_ops_access(%User{} = user, _object) do
    Accounts.tuist_operator?(user)
  end

  def internal_ops_access(_, _), do: false

  @doc """
  Operator READ access to a customer's data. Granted only by an
  active, unexpired operator grant (minted at ops.tuist.dev, verified
  offline, attached to `user.operator_grant`) that covers the object's
  account. Fail-closed: no grant, wrong account, wrong tier, expired,
  or unknown object shape → false.
  """
  def ops_access(%User{} = user, object) do
    operator_grant_covers?(user, object, [:read, :admin])
  end

  def ops_access(_, _), do: false

  @doc """
  Operator ADMIN access to a customer's data ("sign in as admins").
  Requires an `:admin`-tier grant (which only exists after a Slack
  approval), covering the object's account.
  """
  def ops_write_access(%User{} = user, object) do
    operator_grant_covers?(user, object, [:admin])
  end

  def ops_write_access(_, _), do: false

  defp operator_grant_covers?(%User{operator_grant: %{} = grant} = user, object, allowed_tiers) do
    account_id = object_account_id(object)

    # The grant binds to the operator it was minted for: the current user
    # must be a confirmed Tuist operator AND the one named in `sub`. This
    # is the authorization-side half of the bearer-token guard in
    # `TuistWeb.OperatorGrant` (defence in depth — a grant that somehow
    # lands on the wrong session still authorizes nothing).
    Accounts.tuist_operator?(user) and
      operator_grant_subject_matches?(user, grant) and
      not is_nil(account_id) and
      grant[:account_id] == account_id and
      grant[:tier] in allowed_tiers and
      not grant_expired?(grant)
  end

  defp operator_grant_covers?(_user, _object, _allowed_tiers), do: false

  defp operator_grant_subject_matches?(%User{email: email}, %{sub: sub}) when is_binary(email) and is_binary(sub) do
    String.downcase(email) == String.downcase(sub)
  end

  defp operator_grant_subject_matches?(_, _), do: false

  defp grant_expired?(%{exp: exp}) when is_integer(exp), do: exp <= System.system_time(:second)
  defp grant_expired?(_), do: true

  # Resolves any object passed to ops_access/ops_write_access to the
  # customer account id it belongs to (mirrors user_role/3's object
  # handling). Unknown shapes return nil so the grant check fails
  # closed.
  defp object_account_id(%Project{account_id: account_id}), do: account_id
  defp object_account_id(%Account{id: id}), do: id
  defp object_account_id(%{project: %Project{account_id: account_id}}), do: account_id
  defp object_account_id(%{account: %Account{id: id}}), do: id

  defp object_account_id(%{project_id: project_id}) when not is_nil(project_id) do
    case Tuist.Projects.get_project_by_id(project_id) do
      %Project{account_id: account_id} -> account_id
      _ -> nil
    end
  end

  defp object_account_id(_), do: nil

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

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
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
