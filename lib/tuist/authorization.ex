defmodule Tuist.Authorization do
  @moduledoc ~S"""
  A module to deal with authorization in the system.
  """
  alias Tuist.CommandEvents
  alias Tuist.Previews.Preview
  alias Tuist.VCS
  alias Tuist.Environment
  alias Tuist.Projects.Project
  alias Tuist.Accounts
  alias Tuist.Billing
  alias Tuist.Accounts.{User, Account}
  alias Tuist.Repo
  use LetMe.Policy

  object :project_cache do
    action :read do
      desc "Allows the authenticated subject to read a project's cache if the project is public."
      allow :public_project

      desc "Allows users of a project's account to read the project cache."
      allow [:authenticated_as_user, user_role: :user]

      desc "Allows the admin of a project's account to read the project cache."
      allow [:authenticated_as_user, user_role: :admin]

      desc "Allows the authenticated project to read the cache if it matches the project whose cache is being read."
      allow [:authenticated_as_project, :projects_match]
    end
  end

  object :account_registry do
    action :read do
      desc "Allows users of an account to read its registry."
      allow [:authenticated_as_user, user_role: :user]

      desc "Allows the admin of an account to read its registry."
      allow [:authenticated_as_user, user_role: :admin]

      desc "Allows the authenticated account to read the account registry if it matches the account whose registry is being read."
      allow [:authenticated_as_account, :accounts_match, scopes_permit: :account_registry_read]

      desc "Allows the authenticated project to read the cache if it matches the project whose cache is being read."
      allow [:authenticated_as_project, :accounts_match]
    end
  end

  object :account_token do
    action :create do
      desc "Allows users of an account to create an account token."
      allow [:authenticated_as_user, user_role: :user]

      desc "Allows the admin of an account to create an account token."
      allow [:authenticated_as_user, user_role: :admin]
    end
  end

  def can(%User{} = user, :create, %Account{} = account, :project) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
  end

  def can(%User{} = user, :read, %Account{} = account, :project) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
  end

  def can(%User{} = user, :update, %Project{} = project, %{
        repository: %VCS.Repositories.Repository{} = repository
      }) do
    account = Accounts.get_account_by_id(project.account_id)

    if can(user, :update, account, :project) do
      case VCS.get_user_permission(%{user: user, repository: repository}) do
        {:ok, %VCS.Repositories.Permission{permission: permission}} ->
          Enum.member?(["admin", "write"], permission)

        _ ->
          false
      end
    else
      false
    end
  end

  def can(_, :read, %Project{visibility: :public}, :dashboard) do
    true
  end

  def can(nil, :read, %Project{visibility: :private}, :dashboard) do
    false
  end

  def can(%User{} = user, :read, %Project{visibility: :private} = project, :dashboard) do
    account = Accounts.get_account_by_id(project.account_id)
    can(user, :read, account, :project)
  end

  def can(%User{} = user, :update, %Account{} = account, :project) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :delete, %Account{} = account, :project) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :create, %Project{} = project, :cache) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, %{id: project.account_id})
  end

  def can(%User{} = user, :update, %Project{} = project, :cache) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, %{id: project.account_id})
  end

  def can(%User{} = user, :update, %Account{} = account, :billing) do
    subscription = Billing.get_current_active_subscription(account)

    if Environment.on_premise?() or
         (not is_nil(subscription) and subscription.plan == :open_source) do
      false
    else
      Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
    end
  end

  def can(%User{} = user, :read, %Account{} = account, :billing) do
    subscription = Billing.get_current_active_subscription(account)

    if Environment.on_premise?() or
         (not is_nil(subscription) and subscription.plan == :open_source) do
      false
    else
      Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
    end
  end

  def can(nil, :update, _account, :billing) do
    false
  end

  def can(%User{} = user, :read, %Account{} = account, :projects) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
  end

  def can(%User{} = user, :read, %Account{} = account, :organization) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
  end

  def can(%User{} = user, :read, %Account{} = account, :organization_usage) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
  end

  def can(%User{} = user, :update, %Account{} = account, :organization) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :delete, %Account{} = account, :organization) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :create, %Account{} = account, :invitation) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :delete, %Account{} = account, :invitation) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :delete, %Account{} = account, :member) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :update, %Account{} = account, :member) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :create, %Account{} = account, :token) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :read, %Account{} = account, :token) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
  end

  def can(%User{} = user, :delete, %Account{} = account, :token) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :update, %Project{} = project, :settings) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, %{id: project.account_id})
  end

  def can(%Project{} = current_project, :create, %Project{} = project, :preview) do
    current_project.id == project.id
  end

  def can(%User{} = user, :create, %Project{} = project, :preview) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, %{id: project.account_id})
  end

  def can(%User{} = user, :read, %Project{visibility: :private} = project, :preview) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, %{id: project.account_id})
  end

  def can(_, :read, %Project{visibility: :public}, :preview) do
    true
  end

  def can(%Project{} = current_project, :create, %Project{} = project, :cache) do
    current_project.id == project.id
  end

  def can(%Project{} = current_project, :update, %Project{} = project, :cache) do
    current_project.id == project.id
  end

  def can(_, :access, %Project{visibility: :public}, :url) do
    true
  end

  def can(nil, :access, %Project{visibility: :private}, :url) do
    false
  end

  def can(user, :access, %Project{visibility: :private, account: %Account{} = account}, :url) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
  end

  def can(_, :read, %Project{visibility: :public}, :preview) do
    true
  end

  def can(nil, :read, %Project{visibility: :private}, :preview) do
    false
  end

  def can(_, :read, %Preview{type: :ipa}) do
    true
  end

  def can(subject, :read, %Preview{} = preview) do
    preview = preview |> Repo.preload(:project)
    can(subject, :read, preview.project, :preview)
  end

  def can(subject, :read, %CommandEvents.Event{} = command_event) do
    command_event = command_event |> Repo.preload(:project)
    can(subject, :read, command_event.project, :command_event)
  end

  def can(%User{} = user, :read, :ops) do
    env = Tuist.Environment.env()

    if env == :dev do
      true
    else
      user.account.name in Tuist.Environment.ops_user_handles()
    end
  end

  def can(subject, action, project, category, opts \\ [])

  def can(%User{} = user, :create, %Project{} = project, :command_event, opts) do
    is_ci = Keyword.get(opts, :is_ci, false)

    not is_ci and
      Accounts.owns_account_or_belongs_to_account_organization?(user, %{id: project.account_id})
  end

  def can(%User{} = user, :update, %Project{} = project, :command_event, opts) do
    is_ci = Keyword.get(opts, :is_ci, false)

    not is_ci and
      Accounts.owns_account_or_belongs_to_account_organization?(user, %{id: project.account_id})
  end

  def can(%Project{} = current_project, :update, %Project{} = project, :command_event, opts) do
    is_ci = Keyword.get(opts, :is_ci, true)
    is_ci and current_project.id == project.id
  end

  def can(%Project{} = current_project, :create, %Project{} = project, :command_event, opts) do
    is_ci = Keyword.get(opts, :is_ci, true)
    is_ci and current_project.id == project.id
  end

  def can(%User{} = user, :read, %Project{visibility: :private} = project, :command_event, _opts) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, %{id: project.account_id})
  end

  def can(nil, :read, %Project{visibility: :private}, :command_event, _opts) do
    false
  end

  def can(_, :read, %Project{visibility: :public}, :command_event, _opts) do
    true
  end

  def can?(action, subject, object) do
    authorize(action, subject, object) == :ok
  end
end
