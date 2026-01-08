defmodule Tuist.Projects do
  @moduledoc ~S"""
  A module to deal with projects in the system.
  """
  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.ProjectAccount
  alias Tuist.Accounts.User
  alias Tuist.AppBuilds.Preview
  alias Tuist.Base64
  alias Tuist.CommandEvents
  alias Tuist.Projects.Project
  alias Tuist.Projects.ProjectToken
  alias Tuist.Projects.VCSConnection
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
        {:ok, account} = Accounts.get_account_by_id(project.account_id)

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

  @doc """
  Gets projects by their handles (names) for a specific account in a single query.

  Returns `{:ok, projects}` if all handles are found, or `{:error, :not_found, missing_handle}`
  if any handle is not found.
  """
  def get_projects_by_handles_for_account(_account, []), do: {:ok, []}

  def get_projects_by_handles_for_account(%Account{id: account_id}, handles) when is_list(handles) do
    projects =
      Repo.all(
        from(p in Project,
          where: p.account_id == ^account_id and p.name in ^handles
        )
      )

    found_handles = MapSet.new(projects, & &1.name)
    requested_handles = MapSet.new(handles)

    case requested_handles |> MapSet.difference(found_handles) |> MapSet.to_list() do
      [] -> {:ok, projects}
      [missing | _] -> {:error, :not_found, missing}
    end
  end

  @doc """
  Gets projects by their full handles (account_handle/project_handle) in a single query.
  Returns a map of full_handle => project.
  """
  def projects_by_full_handles(full_handles) when is_list(full_handles) do
    handle_pairs =
      full_handles
      |> Enum.map(fn full_handle ->
        case String.split(full_handle, "/") do
          [account_handle, project_handle] -> {account_handle, project_handle}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    account_handles = handle_pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    project_handles = handle_pairs |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    projects =
      from(p in Project,
        join: a in Account,
        on: p.account_id == a.id,
        where: a.name in ^account_handles,
        where: p.name in ^project_handles,
        select: %{project: p, account_name: a.name}
      )
      |> Repo.all()
      |> Map.new(fn %{project: project, account_name: account_name} ->
        full_handle = "#{account_name}/#{project.name}"
        {full_handle, project}
      end)

    handle_pairs
    |> Enum.map(fn {account_handle, project_handle} ->
      full_handle = "#{account_handle}/#{project_handle}"
      {full_handle, Map.get(projects, full_handle)}
    end)
    |> Enum.reject(fn {_full_handle, project} -> is_nil(project) end)
    |> Map.new()
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

  def list_accessible_projects(resource, opts \\ [])

  def list_accessible_projects(%User{} = user, opts) do
    user_account = Accounts.get_account_from_user(user)

    organization_account_ids =
      user
      |> Accounts.get_user_organization_accounts()
      |> Enum.map(& &1.account.id)

    account_ids = [user_account.id | organization_account_ids]
    preload = Keyword.get(opts, :preload, [:account])

    from(p in Project,
      where: p.account_id in ^account_ids,
      preload: ^preload
    )
    |> Repo.all()
    |> maybe_filter_recent(opts)
  end

  def list_accessible_projects(%Account{id: account_id}, opts) do
    preload = Keyword.get(opts, :preload, [:account])

    from(p in Project,
      where: p.account_id == ^account_id,
      preload: ^preload
    )
    |> Repo.all()
    |> maybe_filter_recent(opts)
  end

  def list_accessible_projects(%AuthenticatedAccount{account: account}, opts) do
    list_accessible_projects(account, opts)
  end

  def list_accessible_projects(%Project{} = project, opts) do
    project = Repo.preload(project, Keyword.get(opts, :preload, [:account]))
    [project]
  end

  def list_accessible_projects(_, _opts), do: []

  def get_all_project_accounts(resource, opts \\ []) do
    opts = Keyword.put_new(opts, :preload, [:account])

    resource
    |> list_accessible_projects(opts)
    |> Enum.map(fn project ->
      %ProjectAccount{
        handle: "#{project.account.name}/#{project.name}",
        project: project,
        account: project.account
      }
    end)
  end

  defp maybe_filter_recent(projects, opts) do
    if recent = Keyword.get(opts, :recent) do
      project_ids = Enum.map(projects, & &1.id)
      interaction_data = CommandEvents.get_project_last_interaction_data(project_ids)

      projects
      |> Enum.map(fn project ->
        last_interacted_at = Map.get(interaction_data, project.id, project.updated_at)
        %{project | last_interacted_at: last_interacted_at}
      end)
      |> Enum.sort_by(& &1.last_interacted_at, {:desc, NaiveDateTime})
      |> Enum.take(recent)
    else
      projects
    end
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
      visibility: visibility
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
      default_previews_visibility: Keyword.get(opts, :default_previews_visibility, :private)
    })
    |> Repo.insert!()
    |> Repo.preload(preload)
  end

  def delete_project(%Project{} = project) do
    {:ok, _} =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:delete_command_events, fn _repo, _changes ->
        CommandEvents.delete_project_events(project.id)
        {:ok, :deleted}
      end)
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

      token = Repo.one(from(t in ProjectToken, where: t.id == ^token_id))

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

  def get_repository_url(%Project{} = project) do
    project = Repo.preload(project, :vcs_connection)

    case project.vcs_connection do
      %VCSConnection{provider: :github, repository_full_handle: repository_full_handle} ->
        "https://github.com/#{repository_full_handle}"

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

    interaction_data = CommandEvents.get_project_last_interaction_data(project_ids)

    from(p in Project,
      where: p.id in ^project_ids,
      preload: ^preload
    )
    |> Repo.all()
    |> Enum.map(fn project ->
      last_interacted_at = Map.get(interaction_data, project.id)
      %{project | last_interacted_at: last_interacted_at}
    end)
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
    # Get all interaction data from CommandEvents
    interaction_data = CommandEvents.get_all_project_last_interaction_data()

    # Create a custom Flop query that handles the interaction data
    base_query = from(p in Project, preload: ^preload)

    # Use Flop on the base query, then add interaction data
    {projects, meta} = Flop.validate_and_run!(base_query, attrs, for: Project)

    projects_with_interaction =
      Enum.map(projects, fn project ->
        last_interacted_at = Map.get(interaction_data, project.id)
        %{project | last_interacted_at: last_interacted_at}
      end)

    {projects_with_interaction, meta}
  end

  def get_recent_projects_for_account(account, limit \\ 3) do
    # Get all interaction data from CommandEvents
    interaction_data = CommandEvents.get_all_project_last_interaction_data()

    # Get projects for account and filter/sort by interaction data
    from(p in Project,
      where: p.account_id == ^account.id,
      preload: [:previews]
    )
    |> Repo.all()
    |> Enum.map(fn project ->
      last_interacted_at = Map.get(interaction_data, project.id)
      %{project | last_interacted_at: last_interacted_at}
    end)
    |> Enum.filter(fn project -> not is_nil(project.last_interacted_at) end)
    |> Enum.sort_by(& &1.last_interacted_at, {:desc, NaiveDateTime})
    |> Enum.take(limit)
  end

  @doc """
  Get all projects connected to a VCS repository.
  """
  def projects_by_vcs_repository_full_handle(vcs_repository_full_handle, opts \\ []) do
    preload = Keyword.get(opts, :preload, [:account])

    Repo.all(
      from p in Project,
        join: pc in VCSConnection,
        on: pc.project_id == p.id,
        where: pc.repository_full_handle == ^vcs_repository_full_handle,
        preload: ^preload
    )
  end

  @doc """
  Get a specific project by name and VCS repository handle.
  """
  def project_by_name_and_vcs_repository_full_handle(project_name, vcs_repository_full_handle, opts \\ []) do
    preload = Keyword.get(opts, :preload, [:account])

    project =
      Repo.one(
        from p in Project,
          join: pc in VCSConnection,
          on: pc.project_id == p.id,
          where: pc.repository_full_handle == ^vcs_repository_full_handle and p.name == ^project_name,
          preload: ^preload
      )

    case project do
      nil -> {:error, :not_found}
      _ -> {:ok, project}
    end
  end

  @doc """
  Create a new VCS connection to a repository.
  """
  def create_vcs_connection(attrs) do
    %VCSConnection{}
    |> VCSConnection.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Delete a VCS connection.
  """
  def delete_vcs_connection(%VCSConnection{} = vcs_connection) do
    Repo.delete(vcs_connection)
  end

  @doc """
  Get a VCS connection by ID.
  """
  def get_vcs_connection(id) do
    case Repo.get(VCSConnection, id) do
      nil -> {:error, :not_found}
      connection -> {:ok, connection}
    end
  end
end
