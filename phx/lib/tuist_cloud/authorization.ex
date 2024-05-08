defmodule TuistCloud.Authorization do
  @moduledoc ~S"""
  A module to deal with authorization in the system.
  """
  alias TuistCloud.Projects.Project
  alias TuistCloud.Accounts
  alias TuistCloud.Accounts.{User, Account}

  def can(%User{} = user, :read, %Project{} = project, :cache) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, %{id: project.account_id})
  end

  def can(%User{} = user, :create, %Account{} = account, :project) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
  end

  def can(%User{} = user, :read, %Account{} = account, :project) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
  end

  def can(%User{} = user, :update, %Account{} = account, :project) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :delete, %Account{} = account, :project) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :write, %Project{} = project, :cache) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, %{id: project.account_id})
  end

  def can(%User{} = user, :create, %Project{} = project, :command_event) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, %{id: project.account_id})
  end

  def can(%User{} = user, :update, %Account{} = account, :billing) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :read, %Account{} = account, :organization) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
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

  def can(%Project{} = current_project, :read, %Project{} = project, :cache) do
    current_project.id == project.id
  end

  def can(%Project{} = current_project, :write, %Project{} = project, :cache) do
    current_project.id == project.id
  end

  def can(%Project{} = current_project, :create, %Project{} = project, :command_event) do
    current_project.id == project.id
  end
end
