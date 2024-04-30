defmodule TuistCloud.Projects do
  @moduledoc ~S"""
  A module to deal with projects in the system.
  """
  alias TuistCloud.Repo
  alias TuistCloud.Accounts
  alias TuistCloud.Accounts.{Account, ProjectAccount}
  alias TuistCloud.Projects.Project

  import Ecto.Query

  def get_project_by_token(token) do
    Repo.get_by(Project, token: token)
  end

  def get_project_by_id(project_id) do
    Repo.get_by(Project, id: project_id)
  end

  def get_project_account_by_project_id(project_id) do
    project = get_project_by_id(project_id)

    case project do
      nil ->
        nil

      _ ->
        account = Accounts.get_account_by_id(project.account_id)

        %ProjectAccount{
          handle: "#{account.name}/#{project.name}",
          project: project,
          account: account
        }
    end
  end

  def get_project_by_account_and_project_name(account_name, project_name) do
    with {:account, %{id: account_id}} <- {:account, Repo.get_by(Account, name: account_name)},
         {:project, project} <-
           {:project, Repo.get_by(Project, name: project_name, account_id: account_id)} do
      project
    else
      {:account, nil} -> nil
      {:project, nil} -> nil
    end
  end

  def get_project_by_slug(slug) do
    if String.contains?(slug, "/") do
      [account_name, project_name] = String.split(slug, "/")

      project = get_project_by_account_and_project_name(account_name, project_name)

      if is_nil(project) do
        {:error, :not_found}
      else
        {:ok, project}
      end
    else
      {:error, :missing_handle_or_project_name}
    end
  end

  def get_project_slug_from_id(id) do
    if project = Repo.get(Project, id) |> Repo.preload(:account) do
      "#{project.account.name}/#{project.name}"
    else
      nil
    end
  end

  def get_all_project_accounts(user) do
    user_account = Accounts.get_account_from_user(user)

    organization_account_ids =
      Accounts.get_user_organization_accounts(user)
      |> Enum.map(& &1.account.id)

    account_ids = [user_account.id | organization_account_ids]

    query =
      from p in Project,
        join: a in Account,
        on: p.account_id == a.id,
        where: p.account_id in ^account_ids,
        select: {p, a}

    Repo.all(query)
    |> Enum.map(fn {project, account} ->
      %ProjectAccount{
        handle: "#{account.name}/#{project.name}",
        project: project,
        account: account
      }
    end)
  end

  def create_project(%{name: name, account: %{id: account_id}}, opts \\ []) do
    token = opts |> Keyword.get(:token, TuistCloud.Tokens.generate_authentication_token())

    %Project{}
    |> Project.create_changeset(%{token: token, name: name, account_id: account_id})
    |> Repo.insert!()
  end

  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end
end
