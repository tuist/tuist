defmodule TuistCloud.Authorization do
  @moduledoc ~S"""
  A module to deal with authorization in the system.
  """
  alias TuistCloud.Projects.Project
  alias TuistCloud.Accounts
  alias TuistCloud.Accounts.User

  def can(%User{} = user, :read, %Project{} = project, :cache) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, %{id: project.account_id})
  end

  def can(%User{} = user, :write, %Project{} = project, :cache) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, %{id: project.account_id})
  end

  def can(%Project{} = authenticated_project, :read, %Project{} = project, :cache) do
    authenticated_project.id == project.id
  end

  def can(%Project{} = authenticated_project, :write, %Project{} = project, :cache) do
    authenticated_project.id == project.id
  end
end
