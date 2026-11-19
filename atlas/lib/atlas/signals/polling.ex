defmodule Atlas.Signals.Polling do
  @moduledoc "Opt-in personal account polling with transaction-bound admission and encrypted checkpoints."
  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Automations
  alias Atlas.Automations.Contract
  alias Atlas.Connections
  alias Atlas.Connections.Connection
  alias Atlas.Orbit.Access
  alias Atlas.Repo
  alias Atlas.Signals
  alias Atlas.Signals.Config
  alias Atlas.Signals.Providers
  alias Atlas.Signals.Source
  alias Atlas.Signals.Workers.PollSource
  alias Atlas.Users.User

  def provider("gmail"), do: "google"
  def provider("slack"), do: "slack"
  def scope("gmail"), do: "https://www.googleapis.com/auth/gmail.readonly"
  def scope("slack"), do: "search:read"

  def bind(_actor, nil), do: %{}

  def bind(actor, polling) do
    if not Contract.within_budget?(polling, 4000), do: Repo.rollback(:invalid_source)
    provider = provider(polling["provider"])

    connection =
      Repo.one(from c in Connection, where: c.user_id == ^actor.id and c.provider == ^provider, lock: "FOR SHARE")

    if is_nil(connection) or not Connections.authorized?(actor, provider, [scope(polling["provider"])]),
      do: Repo.rollback(:polling_authorization_required)

    config = Map.put(polling, "binding", Map.take(connection, [:id, :provider_user_id, :workspace_id]))

    %{
      poll_config: JSON.encode!(config),
      poll_interval_seconds: polling["interval_seconds"],
      poll_next_at: DateTime.utc_now()
    }
  end

  def schedule_due do
    if Config.enabled?() do
      now = DateTime.utc_now()

      from(s in Source,
        where: s.enabled and not is_nil(s.poll_config) and s.poll_next_at <= ^now,
        select: s.id
      )
      |> Repo.all()
      |> Enum.each(fn id -> %{"source_id" => id} |> PollSource.new() |> Oban.insert!() end)
    end

    :ok
  end

  def poll(id) do
    with %Source{enabled: true, poll_config: config} = source when not is_nil(config) <- Repo.get(Source, id),
         %User{} = actor <- Repo.get(User, source.owner_id),
         :ok <- authorized(actor, source),
         config = JSON.decode!(source.poll_config),
         state = state(source),
         {:ok, envelopes, page} <- Providers.fetch(config, fn -> read_token(actor, source, config) end, state) do
      commit_page(actor, source, config, state, envelopes, page)
    else
      {:error, reason} -> fail_poll(id, reason)
      _ -> {:cancel, :source_unavailable}
    end
  end

  defp authorized(actor, source) do
    with true <- Config.enabled?(),
         :ok <- Automations.authorize(actor, :write),
         true <- Access.holds_all?(actor, source.required_scopes) do
      :ok
    else
      _ -> {:error, :authorization_lost}
    end
  end

  # A Gmail page makes separate detail requests. Reauthorize each read, not just
  # the batch, so a paused/disconnected account starts no subsequent requests.
  defp read_token(actor, source, config) do
    with %Source{enabled: true} = current <- Repo.get(Source, source.id),
         :ok <- authorized(actor, current) do
      Connections.access_token(
        actor,
        provider(config["provider"]),
        [scope(config["provider"])],
        connection_binding(config)
      )
    else
      _ -> {:error, :authorization_lost}
    end
  end

  defp state(source) do
    stored = if source.poll_state, do: JSON.decode!(source.poll_state), else: %{}
    cursor = stored["cursor"] || DateTime.to_unix(source.inserted_at)

    Map.merge(
      %{
        "cursor" => cursor,
        "start" => max(DateTime.to_unix(source.inserted_at), cursor - 120),
        "end" => DateTime.to_unix(DateTime.utc_now()),
        "page" => nil
      },
      stored
    )
  end

  defp commit_page(actor, snapshot, config, state, envelopes, page) do
    Repo.transaction(fn ->
      source = Repo.one!(from s in Source, where: s.id == ^snapshot.id, lock: "FOR UPDATE")
      if not source.enabled or source.poll_state != snapshot.poll_state, do: Repo.rollback(:stale_poll)
      if authorized(actor, source) != :ok, do: Repo.rollback(:authorization_lost)
      authorize_connection!(actor, config)

      Enum.each(envelopes, fn envelope ->
        envelope = Map.merge(envelope, Map.take(config, ~w(subjects topics)))

        case Signals.ingest(actor, source.id, envelope, interface: "worker") do
          {:ok, _} -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

      persist_progress!(source, state, page)

      Audit.record(
        "signal_source.polled",
        %{target_type: "signal_source", target_id: source.id, metadata: %{count: length(envelopes)}},
        actor: actor,
        interface: "worker"
      )

      if page, do: {:snooze, 1}, else: :ok
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> fail_poll(snapshot.id, reason)
    end
  end

  defp persist_progress!(source, state, page) do
    next_state = if page, do: Map.put(state, "page", page), else: %{"cursor" => state["end"]}
    delay = if page, do: 1, else: source.poll_interval_seconds

    source
    |> Ecto.Changeset.change(
      poll_state: JSON.encode!(next_state),
      poll_next_at: DateTime.add(DateTime.utc_now(), delay, :second),
      poll_error: nil
    )
    |> Repo.update!()
  end

  defp authorize_connection!(actor, config) do
    expected = connection_binding(config)
    connection = Repo.one(from c in Connection, where: c.id == ^expected.id, lock: "FOR SHARE")

    if is_nil(connection) or Map.take(connection, [:id, :provider_user_id, :workspace_id]) != expected or
         not Connections.authorized?(actor, provider(config["provider"]), [scope(config["provider"])]),
       do: Repo.rollback(:authorization_lost)
  end

  defp connection_binding(config) do
    %{
      id: config["binding"]["id"],
      provider_user_id: config["binding"]["provider_user_id"],
      workspace_id: config["binding"]["workspace_id"]
    }
  end

  defp fail_poll(id, reason) do
    category =
      case reason do
        value
        when value in [
               :not_connected,
               :needs_authorization,
               :insufficient_scope,
               :connection_changed,
               :authorization_lost
             ] ->
          "authorization_required"

        {:rate_limited, _} ->
          "rate_limited"

        :stale_poll ->
          "stale_poll"

        _ ->
          "provider_unavailable"
      end

    from(s in Source, where: s.id == ^id)
    |> Repo.update_all(set: [poll_error: category])

    case reason do
      {:rate_limited, seconds} -> {:snooze, seconds}
      :stale_poll -> :ok
      _ -> {:error, category}
    end
  end
end
