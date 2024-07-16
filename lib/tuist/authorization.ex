defmodule Tuist.Authorization do
  @moduledoc ~S"""
  A module to deal with authorization in the system.
  """
  alias Tuist.Projects.Project
  alias Tuist.Accounts
  alias Tuist.Accounts.{User, Account}

  def can(%User{} = user, :read, %Project{visibility: :private} = project, :cache) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, %{id: project.account_id})
  end

  def can(%User{}, :read, %Project{visibility: :public}, :cache) do
    true
  end

  def can(%User{} = user, :create, %Account{} = account, :project) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
  end

  def can(%User{} = user, :read, %Account{} = account, :project) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
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
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :read, %Account{} = account, :billing) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
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

  def can(%Project{} = current_project, :read, %Project{} = project, :cache) do
    current_project.id == project.id
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
end
