defmodule TuistCloud.Projects do
  @moduledoc ~S"""
  A module to deal with projects in the system.
  """
  alias TuistCloud.Repo
  alias TuistCloud.Accounts.Account
  alias TuistCloud.Projects.Project

  def get_project_by_token(token) do
    Repo.get_by(Project, token: token)
  end

  def get_project_by_slug(slug) do
    [account_name, project_name] = String.split(slug, "/")

    with {:account, %{id: account_id}} <- {:account, Repo.get_by(Account, name: account_name)},
         {:project, project} <-
           {:project, Repo.get_by(Project, name: project_name, account_id: account_id)} do
      project
    else
      {:account, nil} -> nil
      {:project, nil} -> nil
    end
  end

  def get_project_slug_from_id(id) do
    if project = Repo.get(Project, id) |> Repo.preload(:account) do
      "#{project.account.name}/#{project.name}"
    else
      nil
    end
  end

  @spec create_project(%{
          :account => %{:id => any(), optional(any()) => any()},
          :name => any(),
          optional(any()) => any()
        }) :: any()
  def create_project(%{name: name, account: %{id: account_id}}, opts \\ []) do
    token = opts |> Keyword.get(:token, TuistCloud.Tokens.generate_authentication_token())

    %Project{}
    |> Project.create_changeset(%{token: token, name: name, account_id: account_id})
    |> Repo.insert!()
  end
end
