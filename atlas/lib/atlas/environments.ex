defmodule Atlas.Environments do
  @moduledoc """
  Owner-private execution environment registrations and project selection.

  The server knows opaque environment/project IDs, permissions and availability,
  not operating systems, filesystem roots or provider credentials. Executors own
  discovery, per-thread workspace preparation and tool execution. The desktop Mac
  is the first executor; another provider can use the same command ledger through
  its own authenticated enrollment/delivery adapter.

  Model sessions and orchestration stay on Atlas. A run freezes its environment
  and project; an offline or unknown executor is never replaced automatically.
  """
  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.CodingRepositories
  alias Atlas.Environments.Environment
  alias Atlas.Environments.Provider
  alias Atlas.Environments.ProviderWorker
  alias Atlas.Orbit
  alias Atlas.Orbit.Access
  alias Atlas.Orbit.Thread
  alias Atlas.Repo
  alias Atlas.Users.User

  @keys ~w(name enabled terminal display projects)

  def list(user) do
    %{
      owner_id: user.id,
      providers: Provider.catalog(),
      environments: Enum.map(Repo.all(from e in Environment, where: e.owner_id == ^user.id), &serialize/1)
    }
  end

  def serialize(environment) do
    Map.take(environment, [:id, :name, :enabled, :terminal, :display, :projects, :provider, :provider_state])
    |> Map.put(:online, online?(environment))
  end

  def online?(%Environment{provider: provider} = environment) when provider != "native" do
    environment.enabled and environment.provider_state == "ready" and match?({:ok, _}, Provider.fetch(provider))
  end

  def online?(environment) do
    environment.enabled and not is_nil(environment.online_until) and
      DateTime.after?(environment.online_until, DateTime.utc_now())
  end

  def register(user, client_id, id, params) do
    with {:ok, id} <- uuid(id), true <- valid_registration?(params) do
      Repo.transaction(fn ->
        # Serialize admission per owner without blocking audit foreign-key reads
        # taken by command transactions that already hold the environment lock.
        Repo.one!(from u in User, where: u.id == ^user.id, lock: "FOR NO KEY UPDATE")
        Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["personal_environment:" <> id])
        existing = Repo.one(from e in Environment, where: e.id == ^id, lock: "FOR UPDATE")

        if existing &&
             (existing.provider != "native" or existing.owner_id != user.id or existing.oauth_client_id != client_id),
           do: Repo.rollback(:not_found)

        if is_nil(existing) && Repo.aggregate(from(e in Environment, where: e.owner_id == ^user.id), :count) >= 32,
          do: Repo.rollback(:environment_limit)

        environment = existing || %Environment{id: id, owner_id: user.id, oauth_client_id: client_id}

        attrs =
          @keys
          |> Map.new(&{String.to_existing_atom(&1), params[&1]})
          |> Map.put(:projects, Enum.map(params["projects"], &canonical_project/1))

        changed? = Enum.any?([:enabled, :terminal, :display, :projects], &(Map.get(environment, &1) != attrs[&1]))

        attrs =
          if changed?,
            do: Map.merge(attrs, %{version: environment.version + 1, online_until: nil, connection_id: nil}),
            else: attrs

        saved = environment |> Ecto.Changeset.change(attrs) |> Repo.insert_or_update!()
        audit(user, saved, "registered")
        saved
      end)
    else
      _ -> {:error, :invalid_params}
    end
  end

  def disable(user, client_id, id) do
    with {:ok, id} <- uuid(id) do
      Repo.transaction(fn ->
        case Repo.one(from e in Environment, where: e.id == ^id, lock: "FOR UPDATE") do
          %Environment{owner_id: owner_id, oauth_client_id: ^client_id, enabled: true} = environment
          when owner_id == user.id ->
            saved =
              environment
              |> Ecto.Changeset.change(
                enabled: false,
                online_until: nil,
                connection_id: nil,
                version: environment.version + 1
              )
              |> Repo.update!()

            audit(user, saved, "disabled")

          _ ->
            :ok
        end

        %{disabled: true}
      end)
    end
  end

  # Only an authenticated fresh join/poll may obtain a new version. Renewals
  # retain the joined version so a stale socket cannot undo a disable/update.
  def renew(user, client_id, id, connection_id, version \\ nil) do
    with {:ok, id} <- uuid(id) do
      Repo.transaction(fn ->
        environment = bound!(user, client_id, id)

        if not environment.enabled or (version && version != environment.version),
          do: Repo.rollback(:environment_disabled)

        environment
        |> Ecto.Changeset.change(
          online_until: DateTime.add(DateTime.utc_now(), 20, :second),
          connection_id: connection_id
        )
        |> Repo.update!()
      end)
    end
  end

  def close(id, connection_id) do
    Repo.update_all(from(e in Environment, where: e.id == ^id and e.connection_id == ^connection_id),
      set: [online_until: nil, connection_id: nil]
    )

    :ok
  end

  def bound!(user, client_id, id) do
    Repo.one(
      from e in Environment,
        where: e.id == ^id and e.owner_id == ^user.id and e.oauth_client_id == ^client_id,
        lock: "FOR UPDATE"
    ) ||
      Repo.rollback(:not_found)
  end

  def select(user, thread_id, params) do
    with {:ok, thread_id} <- uuid(thread_id),
         {:ok, selection} <- selection_ids(params),
         {:ok, repository} <- selection_repository(user, thread_id, params["repository"]) do
      Repo.transaction(fn ->
        thread = Repo.one(from t in Thread, where: t.id == ^thread_id, lock: "FOR UPDATE") || Repo.rollback(:not_found)
        authorize_selection!(user, thread)

        {environment, project_id} = select_environment!(user, thread, selection, repository)
        environment_id = environment && environment.id

        if thread.environment_id && thread.environment_id != environment_id do
          stop_hosted!(thread.environment_id)
        end

        thread
        |> Ecto.Changeset.change(
          environment_id: environment_id,
          environment_name: environment && environment.name,
          project_id: project_id,
          repository: repository,
          last_seq: thread.last_seq + 1
        )
        |> Repo.update!()
        |> Repo.preload(participants: :user)
      end)
      |> tap(fn
        {:ok, thread} ->
          Audit.record("thread.environment_selected", %{
            actor_id: user.id,
            interface: Audit.current_context()[:interface] || "api",
            target_type: "orbit_thread",
            target_id: thread.id
          })

          Orbit.notify_changed(thread.id)

        _ ->
          :ok
      end)
    else
      :error -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  defp authorize_selection!(user, thread) do
    if not Access.can_read?(thread, user), do: Repo.rollback(:not_found)

    case selection_allowed(thread, user) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp selection_ids(%{"provider" => provider} = params) do
    if exact_keys?(params, ["provider"]) and is_binary(provider) and match?({:ok, _}, Provider.fetch(provider)),
      do: {:ok, {:provider, provider}},
      else: {:error, :invalid_params}
  end

  defp selection_ids(params) do
    with true <-
           exact_keys?(params, ~w(environment_id project_id)) or
             exact_keys?(params, ~w(environment_id project_id repository)),
         {:ok, environment_id} <- nullable_uuid(params["environment_id"]),
         {:ok, project_id} <- nullable_uuid(params["project_id"]),
         true <- not is_nil(environment_id) or is_nil(project_id) do
      {:ok, {:native, environment_id, project_id}}
    else
      _ -> {:error, :invalid_params}
    end
  end

  defp selection_repository(_user, _thread_id, nil), do: {:ok, nil}

  defp selection_repository(user, thread_id, repository) do
    # Authorize before the remote lookup, then recheck under the thread lock.
    # Never hold a database transaction open while requesting GitHub metadata.
    with {:ok, thread} <- Orbit.fetch(user, thread_id),
         :ok <- selection_allowed(thread, user) do
      CodingRepositories.authorize_repository(user, repository)
    end
  end

  defp selection_allowed(thread, user) do
    cond do
      thread.kind != "private" or thread.owner_id != user.id -> {:error, :private_environment_required}
      thread.status != "active" -> {:error, :archived}
      Orbit.active_run(thread) -> {:error, :environment_run_active}
      true -> :ok
    end
  end

  defp select_environment!(user, thread, {:provider, provider}, _repository) do
    {:ok, config} = Provider.fetch(provider)
    Repo.one!(from u in User, where: u.id == ^user.id, lock: "FOR NO KEY UPDATE")

    existing =
      Repo.one(
        from e in Environment,
          where: e.owner_id == ^user.id and e.managed_thread_id == ^thread.id and e.provider == ^provider,
          lock: "FOR UPDATE"
      )

    if is_nil(existing) and Repo.aggregate(from(e in Environment, where: e.owner_id == ^user.id), :count) >= 32,
      do: Repo.rollback(:environment_limit)

    environment =
      existing ||
        %Environment{
          id: Ecto.UUID.generate(),
          owner_id: user.id,
          oauth_client_id: Ecto.UUID.generate(),
          provider: provider,
          managed_thread_id: thread.id,
          name: config.name,
          projects: [%{"id" => Ecto.UUID.generate(), "name" => "Workspace"}]
        }

    environment =
      environment
      |> Ecto.Changeset.change(
        enabled: true,
        terminal: true,
        provider_state: "starting",
        version: environment.version + 1
      )
      |> Repo.insert_or_update!()
      |> tap(&enqueue_lifecycle!/1)

    {environment, hd(environment.projects)["id"]}
  end

  defp select_environment!(_user, _thread, {:native, nil, nil}, _repository), do: {nil, nil}

  defp select_environment!(user, _thread, {:native, id, project_id}, repository) do
    environment = owned_enabled!(user.id, id, project_id)

    if environment.provider != "native",
      do: Repo.rollback(:environment_disabled)

    if repository &&
         not Enum.any?(environment.projects, &(&1["id"] == project_id and &1["repository"] == repository)),
       do: Repo.rollback(:environment_repository_mismatch)

    {environment, project_id}
  end

  def stop_hosted!(id) do
    case Repo.one(from e in Environment, where: e.id == ^id, lock: "FOR UPDATE") do
      %Environment{provider: provider, enabled: true} = environment when provider != "native" ->
        environment
        |> Ecto.Changeset.change(enabled: false, provider_state: "stopping", version: environment.version + 1)
        |> Repo.update!()
        |> tap(&enqueue_lifecycle!/1)

      _ ->
        :ok
    end
  end

  defp enqueue_lifecycle!(environment) do
    %{environment_id: environment.id}
    |> ProviderWorker.new()
    |> Oban.insert!()
  end

  def owned_enabled!(owner_id, id, project_id) do
    environment = Repo.one(from e in Environment, where: e.id == ^id and e.owner_id == ^owner_id, lock: "FOR UPDATE")
    if is_nil(environment) or not environment.enabled, do: Repo.rollback(:environment_disabled)

    if project_id && not Enum.any?(environment.projects, &(&1["id"] == project_id)),
      do: Repo.rollback(:environment_project_unavailable)

    environment
  end

  def uuid(value) when is_binary(value), do: Ecto.UUID.cast(value)
  def uuid(_value), do: :error
  defp nullable_uuid(nil), do: {:ok, nil}
  defp nullable_uuid(value), do: uuid(value)

  def exact_keys?(params, keys) when is_map(params), do: Enum.sort(Map.keys(params)) == Enum.sort(keys)
  def exact_keys?(_params, _keys), do: false

  defp valid_registration?(params) do
    exact_keys?(params, @keys) and name?(params["name"]) and
      Enum.all?(~w(enabled terminal display), &is_boolean(params[&1])) and projects?(params["projects"])
  end

  defp projects?(projects) when is_list(projects) and length(projects) <= 100 do
    Enum.all?(projects, &project?/1) and
      length(Enum.uniq_by(projects, &Ecto.UUID.cast!(&1["id"]))) == length(projects)
  end

  defp projects?(_projects), do: false

  defp project?(project) do
    is_map(project) and Enum.all?(Map.keys(project), &(&1 in ~w(id name coding repository))) and
      match?({:ok, _}, uuid(project["id"])) and name?(project["name"]) and
      (not Map.has_key?(project, "coding") or is_boolean(project["coding"])) and
      (not Map.has_key?(project, "repository") or
         (project["coding"] == true and CodingRepositories.repository?(project["repository"])))
  end

  defp canonical_project(project) do
    project = Map.put(project, "id", Ecto.UUID.cast!(project["id"]))

    if Map.has_key?(project, "repository"),
      do: Map.update!(project, "repository", &String.downcase/1),
      else: project
  end

  defp name?(name) when is_binary(name),
    do:
      String.valid?(name) and byte_size(name) <= 400 and String.length(name) in 1..100 and String.trim(name) != "" and
        not String.contains?(name, ["/", "\\", "\n", "\r", <<0>>])

  defp name?(_name), do: false

  defp audit(user, environment, action) do
    Audit.record("environment.#{action}", %{
      actor_id: user.id,
      interface: "api",
      target_type: "personal_environment",
      target_id: environment.id,
      metadata: %{
        enabled: environment.enabled,
        terminal: environment.terminal,
        display: environment.display,
        project_count: length(environment.projects)
      }
    })
  end
end
