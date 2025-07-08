defmodule Tuist.Projects do
  @moduledoc ~S"""
  A module to deal with projects in the system.
  """
  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.ProjectAccount
  alias Tuist.Accounts.User
  alias Tuist.AppBuilds.Preview
  alias Tuist.Base64
  alias Tuist.CommandEvents.Event
  alias Tuist.Projects.Project
  alias Tuist.Projects.ProjectToken
  alias Tuist.Repo

  def get_projects_count do
    Repo.aggregate(Project, :count, :id)
  end

  def get_project_count_for_account(%Account{id: account_id}) do
    query = from p in Project, where: p.account_id == ^account_id
    Repo.aggregate(query, :count, :id)
  end

  def legacy_token?(token) do
    not String.starts_with?(token, "tuist_")
  end

  def get_project_by_full_token(full_token) do
    if legacy_token?(full_token) do
      Repo.one(from(p in Project, where: p.token == ^full_token, preload: [:account]))
    else
      case get_project_token(full_token) do
        {:error, _} -> nil
        {:ok, token} -> get_project_by_id(token.project_id)
      end
    end
  end

  def get_project_by_id(project_id) do
    Repo.one(from(p in Project, where: p.id == ^project_id, preload: [:account]))
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

  def get_project_by_account_and_project_handles(account_handle, project_handle, opts \\ []) do
    with {:account, %{id: account_id}} <-
           {:account,
            Repo.one(
              from a in Account,
                where: a.name == ^account_handle
            )},
         {:project, project} <-
           {:project,
            Repo.one(
              from(p in Project,
                where: p.name == ^project_handle,
                where: p.account_id == ^account_id
              )
            )} do
      Repo.preload(project, Keyword.get(opts, :preload, [:account]))
    else
      {:account, nil} -> nil
      {:project, nil} -> nil
    end
  end

  def get_project_by_slug(slug, opts \\ []) do
    components = String.split(slug, "/")

    case components do
      [account_name, project_name] ->
        project = get_project_by_account_and_project_handles(account_name, project_name, opts)

        if is_nil(project) do
          {:error, :not_found}
        else
          {:ok, project}
        end

      _ ->
        {:error, :invalid}
    end
  end

  def get_project_slug_from_id(id) do
    if project = Repo.one(from p in Project, where: p.id == ^id, preload: [:account]) do
      "#{project.account.name}/#{project.name}"
    end
  end

  def get_all_project_accounts(%User{} = user) do
    user_account = Accounts.get_account_from_user(user)

    organization_account_ids =
      user
      |> Accounts.get_user_organization_accounts()
      |> Enum.map(& &1.account.id)

    account_ids = [user_account.id | organization_account_ids]

    query =
      from p in Project,
        join: a in Account,
        on: p.account_id == a.id,
        where: p.account_id in ^account_ids,
        select: %{project: p, account: a}

    query
    |> Repo.all()
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

    query
    |> Repo.all()
    |> Enum.map(fn project ->
      %ProjectAccount{
        handle: "#{account.name}/#{project.name}",
        project: project,
        account: account
      }
    end)
  end

  def create_project(%{name: name, account: %{id: account_id}}, opts \\ []) do
    token = Keyword.get(opts, :token, Tuist.Tokens.generate_token())
    created_at = Keyword.get(opts, :created_at, DateTime.utc_now())
    visibility = Keyword.get(opts, :visibility, :private)

    %{
      token: token,
      name: name,
      account_id: account_id,
      created_at: created_at,
      visibility: visibility,
      vcs_repository_full_handle: Keyword.get(opts, :vcs_repository_full_handle),
      vcs_provider: Keyword.get(opts, :vcs_provider)
    }
    |> Project.create_changeset()
    |> Repo.insert()
  end

  def create_project!(%{name: name, account: %{id: account_id}}, opts \\ []) do
    token = Keyword.get(opts, :token, Tuist.Tokens.generate_token())
    created_at = Keyword.get(opts, :created_at, DateTime.utc_now())
    visibility = Keyword.get(opts, :visibility, :private)
    preload = Keyword.get(opts, :preload, [])

    %Project{}
    |> Project.create_changeset(%{
      token: token,
      name: name,
      account_id: account_id,
      created_at: created_at,
      visibility: visibility,
      vcs_repository_full_handle: Keyword.get(opts, :vcs_repository_full_handle),
      vcs_provider: Keyword.get(opts, :vcs_provider)
    })
    |> Repo.insert!()
    |> Repo.preload(preload)
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
      Bcrypt.hash_pwd_salt(token_hash <> Tuist.Environment.secret_key_password())

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
    Repo.all(from(t in ProjectToken, where: t.project_id == ^project.id))
  end

  def get_project_token_by_id(%Project{} = project, token_id) do
    Repo.one(from(t in ProjectToken, where: t.id == ^token_id and t.project_id == ^project.id))
  end

  def get_project_token(full_token) do
    full_token_components = String.split(full_token, "_")

    if length(full_token_components) == 3 do
      [_audience, token_id, token_hash] = full_token_components

      token = Tuist.Repo.one(from(t in ProjectToken, where: t.id == ^token_id))

      cond do
        is_nil(token) ->
          {:error, :not_found}

        verify_pass(token, token_hash) ->
          {:ok, token}

        true ->
          {:error, :invalid_token}
      end
    else
      {:error, :invalid_token}
    end
  end

  # Bcrypt does CPU-intensive operations and it can easily slow-down requests when
  # there are bursts of requests coming through the API.
  def verify_pass(token, token_hash) do
    Bcrypt.verify_pass(
      token_hash <> Tuist.Environment.secret_key_password(),
      token.encrypted_token_hash
    )
  end

  def revoke_project_token(%ProjectToken{} = token) do
    Repo.delete(token)
  end

  def update_project(%Project{} = project, attrs) do
    project
    |> Project.update_changeset(attrs)
    |> Repo.update()
  end

  def get_repository_url(%Project{vcs_provider: vcs_provider, vcs_repository_full_handle: vcs_repository_full_handle}) do
    case vcs_provider do
      :github ->
        "https://github.com/#{vcs_repository_full_handle}"

      nil ->
        nil
    end
  end

  def platforms(project, opts \\ []) do
    device_platforms_only? = Keyword.get(opts, :device_platforms_only?, false)

    integers =
      Repo.all(
        from(p in Preview,
          where: p.project_id == ^project.id,
          select: fragment("DISTINCT UNNEST(?)", p.supported_platforms)
        )
      )

    {:array, {:parameterized, {Ecto.Enum, enum_opts_map}}} =
      Preview.__schema__(:type, :supported_platforms)

    mappings_kv = Map.fetch!(enum_opts_map, :mappings)
    int_to_atom_map = Map.new(mappings_kv, fn {atom, int} -> {int, atom} end)

    platforms = Enum.map(integers, &Map.get(int_to_atom_map, &1))

    if device_platforms_only? do
      Preview.map_simulators_to_devices(platforms)
    else
      platforms
    end
  end

  def list_sorted_with_interaction_data(projects, opts \\ []) do
    project_ids = Enum.map(projects, & &1.id)
    preload = Keyword.get(opts, :preload, [])

    from(p in Project,
      left_join:
        ce_max in subquery(
          from(ce in Event,
            where: ce.project_id in ^project_ids,
            group_by: ce.project_id,
            select: %{project_id: ce.project_id, last_interacted_at: max(ce.ran_at)}
          )
        ),
      on: p.id == ce_max.project_id,
      where: p.id in ^project_ids,
      select: %{p | last_interacted_at: ce_max.last_interacted_at}
    )
    |> preload(^preload)
    |> Repo.all()
    |> Enum.sort_by(
      fn project ->
        case project.last_interacted_at do
          nil -> {1, project.created_at}
          last_interacted_at -> {0, last_interacted_at}
        end
      end,
      fn {priority_a, date_a}, {priority_b, date_b} ->
        case {priority_a, priority_b} do
          {same, same} -> NaiveDateTime.after?(date_a, date_b)
          {a, b} -> a < b
        end
      end
    )
  end

  def list_projects(attrs, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])
    include_interaction_data = Keyword.get(opts, :include_interaction_data, false)

    if include_interaction_data do
      list_projects_with_interaction_data(attrs, preload)
    else
      Project
      |> preload(^preload)
      |> Flop.validate_and_run!(attrs, for: Project)
    end
  end

  defp list_projects_with_interaction_data(attrs, preload) do
    subquery =
      from(ce in Event,
        group_by: ce.project_id,
        select: %{project_id: ce.project_id, last_interacted_at: max(ce.ran_at)}
      )

    Flop.validate_and_run!(
      from(p in Project,
        left_join: ce_max in subquery(subquery),
        on: p.id == ce_max.project_id,
        select: %{p | last_interacted_at: ce_max.last_interacted_at},
        preload: ^preload
      ),
      attrs,
      for: Project
    )
  end

  def get_recent_projects_for_account(account, limit \\ 3) do
    event_subquery =
      from(ce in Event,
        group_by: ce.project_id,
        select: %{project_id: ce.project_id, last_interacted_at: max(ce.ran_at)}
      )

    Repo.all(
      from(p in Project,
        join: ce_max in subquery(event_subquery),
        on: p.id == ce_max.project_id,
        where: p.account_id == ^account.id and not is_nil(ce_max.last_interacted_at),
        select: %{p | last_interacted_at: ce_max.last_interacted_at},
        order_by: [desc: ce_max.last_interacted_at],
        limit: ^limit,
        preload: [:previews]
      )
    )
  end
end
