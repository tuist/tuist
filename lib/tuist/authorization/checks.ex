defmodule Tuist.Authorization.Checks do
  @moduledoc ~S"""
  This module contains check functions for the authorization of users and projects.
  """
  alias Tuist.Accounts.{User}
  alias Tuist.Projects.Project
  alias Tuist.Accounts

  def user_role(%User{} = authenticated_user, %Project{} = project, role)
      when role in [:user, :admin] do
    Accounts.owns_account_or_belongs_to_account_organization?(authenticated_user, %{
      id: project.account_id
    })
  end

  def user_role(%Project{}, _, _) do
    false
  end

  def matches_authenticated_project(%User{}, %Project{}) do
    false
  end

  def matches_authenticated_project(%Project{} = authenticated_project, %Project{} = project) do
    authenticated_project.id == project.id
  end

  def public_project(_, %Project{visibility: :public}) do
    true
  end

  def public_project(_, %Project{}) do
    false
  end
end
