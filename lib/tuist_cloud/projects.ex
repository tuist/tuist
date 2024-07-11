defmodule TuistCloud.Projects do
  @moduledoc ~S"""
  A module to deal with projects in the system.
  """
  alias TuistCloud.Base64
  alias TuistCloud.CommandEvents.Event
  alias TuistCloud.Repo
  alias TuistCloud.Accounts
  alias TuistCloud.Accounts.{Account, ProjectAccount, User}
  alias TuistCloud.Projects.Project
  alias TuistCloud.Projects.ProjectToken

  import Ecto.Query

  def legacy_token?(token) do
    not String.starts_with?(token, "tuist_")
  end

  def get_project_by_full_token(full_token) do
    if full_token |> legacy_token?() do
      Repo.get_by(Project, token: full_token)
    else
      case get_project_token(full_token) do
        {:error, _} -> nil
        {:ok, token} -> get_project_by_id(token.project_id)
      end
    end
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

  def get_project_and_account_handles_from_full_handle(full_handle) do
    components = String.split(full_handle, "/")

    if length(components) == 2 do
      [account_handle, project_handle] = components
      {:ok, %{account_handle: account_handle, project_handle: project_handle}}
    else
      {:error, :invalid_full_handle}
    end
  end

  def get_project_by_account_and_project_handles(account_name, project_name, opts \\ []) do
    with {:account, %{id: account_id}} <-
           {:account,
            Repo.one(
              from a in Account,
                where: fragment("lower(?)", a.name) == ^String.downcase(account_name)
            )},
         {:project, project} <-
           {:project,
            Repo.one(
              from(p in Project,
                where: fragment("lower(?)", p.name) == ^String.downcase(project_name),
                where: p.account_id == ^account_id
              )
            )} do
      project |> Repo.preload(Keyword.get(opts, :preloads, []))
    else
      {:account, nil} -> nil
      {:project, nil} -> nil
    end
  end

  def get_project_by_slug(slug, opts \\ []) do
    if String.contains?(slug, "/") do
      [account_name, project_name] = String.split(slug, "/")

      project = get_project_by_account_and_project_handles(account_name, project_name, opts)

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
        select: %{project: p, account: a}

    Repo.all(query)
    |> Enum.map(fn %{project: project, account: account} ->
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
    preloads = opts |> Keyword.get(:preloads, [])

    %Project{}
    |> Project.create_changeset(%{
      token: token,
      name: name,
      account_id: account_id,
      created_at: created_at,
      visibility: visibility
    })
    |> Repo.insert!()
    |> Repo.preload(preloads)
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

  def create_project_token(%Project{} = project) do
    token_hash = Base64.encode(:crypto.strong_rand_bytes(20))

    encrypted_token_hash =
      Bcrypt.hash_pwd_salt(token_hash <> TuistCloud.Environment.secret_key_password())

    token =
      %ProjectToken{}
      |> ProjectToken.create_changeset(%{
        project_id: project.id,
        encrypted_token_hash: encrypted_token_hash
      })
      |> Repo.insert!()

    "tuist_#{token.id}_#{token_hash}"
  end

  def get_project_tokens(%Project{} = project) do
    from(t in ProjectToken, where: t.project_id == ^project.id)
    |> Repo.all()
  end

  def get_project_token_by_id(%Project{} = project, token_id) do
    from(t in ProjectToken, where: t.id == ^token_id and t.project_id == ^project.id)
    |> Repo.one()
  end

  def get_project_token(full_token) do
    full_token_components = String.split(full_token, "_")

    if length(full_token_components) != 3 do
      {:error, :invalid_token}
    else
      [_audience, token_id, token_hash] = full_token_components

      token =
        from(t in ProjectToken,
          where: t.id == ^token_id
        )
        |> TuistCloud.Repo.one()

      cond do
        is_nil(token) ->
          {:error, :not_found}

        Bcrypt.verify_pass(
          token_hash <> TuistCloud.Environment.secret_key_password(),
          token.encrypted_token_hash
        ) ->
          {:ok, token}

        true ->
          {:error, :invalid_token}
      end
    end
  end

  def revoke_project_token(%ProjectToken{} = token) do
    Repo.delete(token)
  end
end
