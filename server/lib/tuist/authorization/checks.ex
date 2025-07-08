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

  def public_project(_, %Project{}) do
    false
  end
end
