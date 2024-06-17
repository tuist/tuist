defmodule TuistCloud.Projects do
  @moduledoc ~S"""
  A module to deal with projects in the system.
  """
  alias TuistCloud.CommandEvents.Event
  alias TuistCloud.Repo
  alias TuistCloud.Accounts
  alias TuistCloud.Accounts.{Account, ProjectAccount, User}
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
    with {:account, %{id: account_id}} <-
           {:account,
            Repo.one(
              from a in Account,
                where: fragment("lower(?)", a.name) == ^String.downcase(account_name)
            )},
         {:project, project} <-
           {:project,
            Repo.one(
              from p in Project,
                where: fragment("lower(?)", p.name) == ^String.downcase(project_name),
                where: p.account_id == ^account_id
            )} do
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

  def get_all_project_accounts(%User{} = user) do
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

  def get_all_project_accounts(%Account{id: account_id} = account) do
    query = from p in Project, where: p.account_id == ^account_id, select: p

    Repo.all(query)
    |> Enum.map(fn project ->
      %ProjectAccount{
        handle: "#{account.name}/#{project.name}",
        project: project,
        account: account
      }
    end)
  end

  def create_project(%{name: name, account: %{id: account_id}}, opts \\ []) do
    token = opts |> Keyword.get(:token, TuistCloud.Tokens.generate_token())
    created_at = opts |> Keyword.get(:created_at, DateTime.utc_now())
    visibility = opts |> Keyword.get(:visibility, :private)

    %Project{}
    |> Project.create_changeset(%{
      token: token,
      name: name,
      account_id: account_id,
      created_at: created_at,
      visibility: visibility
    })
    |> Repo.insert!()
  end

  def delete_project(%Project{} = project) do
    {:ok, _} =
      Ecto.Multi.new()
      |> Ecto.Multi.delete_all(
        :delete_command_events,
        from(
          c in Event,
          where: c.project_id == ^project.id
        )
      )
      |> Ecto.Multi.delete(:delete_project, project)
      |> Repo.transaction()
  end
end
