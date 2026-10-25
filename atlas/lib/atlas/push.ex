defmodule Atlas.Push do
  @moduledoc """
  Native push notification registrations and delivery intents.

  Product code asks for a notification with `notify_user/3` using a fixed kind
  and a native destination; it never supplies text, tokens or recipients'
  devices. Delivery fans out to one durable Oban job per registration whose
  arguments contain only IDs, so provider tokens live solely in the encrypted
  `push_installations` table. Registration, retirement, enqueue and delivery
  outcomes are audited with bounded metadata and never tokens. See
  `lib/atlas/push/AGENTS.md`.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Push.Config
  alias Atlas.Push.Installation
  alias Atlas.Push.Workers.Deliver
  alias Atlas.Repo
  alias Atlas.Users.User
  alias AtlasWeb.NativeLinks

  @max_live_per_user 10
  @session_sweep_batch 1000
  @stale_after_days 60
  @tombstone_retention_days 180
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  @ios_token ~r/\A(?:[0-9a-fA-F]{2}){16,256}\z/
  @android_token ~r/\A[\x21-\x7E]{16,4096}\z/
  @body_keys ~w(platform token environment)

  # Kind => seconds before an undelivered notification is no longer useful.
  # Orbit source-backed kinds reauthorize the exact message at send time.
  @kinds %{"activity" => 86_400, "self_test" => 600, "orbit_completed" => 3600, "orbit_mentioned" => 3600}

  def kinds, do: Map.keys(@kinds)

  def capabilities, do: Config.capabilities()

  @doc """
  Registers or refreshes `installation_id` for `user`.

  Returns `{:ok, installation}`, or `{:error, reason}` where reason is
  `:invalid`, `:unavailable` (provider not configured), `:retired` (the ID is a
  tombstone; the client must rotate to a new UUID), or `:conflict` (another
  user's live installation that this OAuth client cannot prove it owns).
  """
  def register(%User{} = user, oauth_client_id, installation_id, params, opts \\ [])
      when is_binary(oauth_client_id) and is_map(params) do
    with {:ok, installation_id} <- validate_installation_id(installation_id),
         {:ok, attrs} <- validate_device(params),
         :ok <- ensure_available(attrs.platform, attrs.environment) do
      token_hash = Installation.token_hash(attrs.platform, attrs.token)
      audit = audit_opts(user, opts)

      installation_id
      |> locked(fn existing -> upsert(existing, user, oauth_client_id, installation_id, attrs, token_hash, audit) end)
      |> case do
        {:ok, {:ok, installation}} -> {:ok, installation}
        {:ok, {:error, reason}} -> {:error, reason}
        {:error, %Ecto.Changeset{}} -> {:error, :conflict}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Retires `installation_id` when it belongs to `user` or was registered through
  the same OAuth client (the app installation's own client registration, which
  lets the next signed-in user clean up after an offline sign-out). Unknown IDs
  become tombstones so a registration arriving after its deletion is rejected.
  Other users' installations are left untouched. Always `:ok` for a valid ID.
  """
  def unregister(%User{} = user, oauth_client_id, installation_id, opts \\ []) when is_binary(oauth_client_id) do
    audit = audit_opts(user, opts)

    with {:ok, installation_id} <- validate_installation_id(installation_id) do
      installation_id
      |> locked(fn
        nil ->
          insert_tombstone!(installation_id, oauth_client_id, audit)

        %Installation{retired_at: %DateTime{}} ->
          :ok

        %Installation{} = installation ->
          if installation.user_id == user.id or installation.oauth_client_id == oauth_client_id do
            retire!(installation, "unregistered", audit)
          end

          :ok
      end)
      |> case do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Queues `kind` for every live registration of `user_id` on configured
  platforms. `destination` is `{screen, record_id | nil}` from the native
  destination allowlist. Returns `{:ok, queued_count}`.

  `orbit_completed` requires `opts[:message_id]`, the exact committed agent
  reply. Jobs carry that ID, never the reply text; delivery reauthorizes its
  thread and succeeded run before deriving a bounded preview. Other kinds
  retain generic alerts.

  `orbit_mentioned` also requires `opts[:message_id]`, but names the exact human
  source whose selected mentions contain the recipient. Delivery rechecks active
  shared membership and history scopes before sending a generic ping.

  Each call creates a fresh notification ID and at most one job per
  registration. The worker declares uniqueness on `[registration_id,
  notification_id]`, but `Oban.insert_all/1` on the Basic engine does not
  enforce it; distinct registration IDs and a fresh notification ID are what
  prevent duplicates here.
  """
  def notify_user(user_id, kind, destination, opts \\ []) when is_binary(user_id) do
    with {:ok, ttl} <- Map.fetch(@kinds, kind),
         true <- valid_notification?(kind, destination),
         {:ok, source} <- notification_source(kind, opts) do
      {screen, record_id} = destination
      notification_id = Ecto.UUID.generate()
      expires_at = DateTime.add(DateTime.utc_now(), ttl)
      platforms = for {platform, true} <- Config.capabilities(), do: platform

      jobs =
        from(i in Installation, as: :installation)
        |> where([i], i.user_id == ^user_id and is_nil(i.retired_at) and i.platform in ^platforms)
        |> where(exists(active_grant()))
        |> select([i], i.id)
        |> Repo.all()
        |> Enum.map(fn registration_id ->
          %{
            registration_id: registration_id,
            user_id: user_id,
            notification_id: notification_id,
            kind: kind,
            screen: screen,
            record_id: record_id,
            expires_at: DateTime.to_iso8601(expires_at)
          }
          |> Map.merge(source)
          |> Deliver.new()
        end)

      queued = jobs |> Oban.insert_all() |> length()

      Audit.record(
        "push_notification.queued",
        %{
          target_type: "user",
          target_id: user_id,
          metadata: %{
            "notification_id" => notification_id,
            "kind" => kind,
            "screen" => screen,
            "record_id" => record_id,
            "queued" => queued
          }
        },
        opts
      )

      {:ok, queued}
    else
      _ -> {:error, :invalid_notification}
    end
  end

  @doc "Whether queued job arguments still describe an allowed kind and destination."
  def valid_notification?(kind, {"orbit", record_id} = destination)
      when kind in ["orbit_completed", "orbit_mentioned"] and is_binary(record_id), do: valid_destination?(destination)

  def valid_notification?(kind, _destination) when kind in ["orbit_completed", "orbit_mentioned"], do: false

  def valid_notification?(kind, destination), do: Map.has_key?(@kinds, kind) and valid_destination?(destination)

  defp notification_source(kind, opts) when kind in ["orbit_completed", "orbit_mentioned"] do
    case Ecto.UUID.cast(Keyword.get(opts, :message_id)) do
      {:ok, message_id} -> {:ok, %{message_id: message_id}}
      :error -> :error
    end
  end

  defp notification_source(_kind, _opts), do: {:ok, %{}}

  @doc """
  The live registration a job may deliver to, re-checked at send time. A
  registration whose app session has ended (see `active_grant/0`) is retired
  with reason `session_ended` instead of being returned.
  """
  def deliverable(registration_id, user_id) do
    with {:ok, registration_id} <- Ecto.UUID.cast(registration_id),
         {:ok, user_id} <- Ecto.UUID.cast(user_id) do
      live =
        from(i in Installation, as: :installation)
        |> where([i], i.id == ^registration_id and i.user_id == ^user_id and is_nil(i.retired_at))

      ended = live |> where(not exists(active_grant())) |> select([i], i)

      case Repo.update_all(ended, set: retired_fields("session_ended")) do
        {0, _} ->
          Repo.one(live)

        {1, [installation]} ->
          audit_retired(installation, "session_ended", interface: "worker")
          nil
      end
    else
      :error -> nil
    end
  end

  @doc """
  Compare-and-retire after a definitive provider rejection. Only retires when the
  registration still holds the rejected token in the same environment, so a token
  or environment changed mid-delivery survives. `unregistered_at` (APNs 410)
  skips registrations refreshed after Apple's last-invalid timestamp, even with
  the same token.
  """
  def retire_invalidated(%Installation{} = installation, opts \\ []) do
    query =
      where(
        Installation,
        [i],
        i.id == ^installation.id and i.token_hash == ^installation.token_hash and
          i.environment == ^installation.environment and is_nil(i.retired_at)
      )

    query =
      case Keyword.get(opts, :unregistered_at) do
        %DateTime{} = at -> where(query, [i], i.last_registered_at < ^at)
        nil -> query
      end

    case Repo.update_all(query, set: retired_fields("provider_invalidated")) do
      {1, _} ->
        audit_retired(installation, "provider_invalidated", interface: "worker")
        :retired

      {0, _} ->
        :kept
    end
  end

  @doc """
  Retires registrations the app has not refreshed for #{@stale_after_days} days
  (clients re-register on foreground) and deletes tombstones after
  #{@tombstone_retention_days} days.
  """
  def prune do
    now = DateTime.utc_now()

    # Bounded sweep of registrations whose app session ended without a DELETE,
    # for example a rejected refresh or a discarded client registration.
    ended_ids =
      from(i in Installation, as: :installation)
      |> where([i], is_nil(i.retired_at))
      |> where(not exists(active_grant()))
      |> limit(@session_sweep_batch)
      |> select([i], i.id)

    {ended, _} =
      Installation
      |> where([i], i.id in subquery(ended_ids) and is_nil(i.retired_at))
      |> Repo.update_all(set: retired_fields("session_ended"))

    {stale, _} =
      Installation
      |> where([i], is_nil(i.retired_at) and i.last_registered_at < ^DateTime.add(now, -@stale_after_days, :day))
      |> Repo.update_all(set: retired_fields("stale"))

    {deleted, _} =
      Installation
      |> where([i], i.retired_at < ^DateTime.add(now, -@tombstone_retention_days, :day))
      |> Repo.delete_all()

    if ended + stale + deleted > 0 do
      Audit.record(
        "push_installation.pruned",
        %{metadata: %{"session_ended" => ended, "retired" => stale, "deleted" => deleted}},
        interface: "worker"
      )
    end

    {:ok, %{session_ended: ended, retired: stale, deleted: deleted}}
  end

  @doc false
  def audit_delivery(%Installation{} = installation, args, outcome, reason \\ nil) do
    Audit.record(
      "push_notification.delivery",
      %{
        target_type: "push_installation",
        target_id: installation.id,
        metadata:
          %{
            "outcome" => outcome,
            "notification_id" => args["notification_id"],
            "kind" => args["kind"],
            "platform" => installation.platform,
            "environment" => installation.environment
          }
          |> put_reason(reason)
      },
      interface: "worker"
    )
  end

  # A registration is deliverable only while the OAuth client it was registered
  # through still holds an active refresh grant for the same user. Boruta stores
  # each refresh rotation as a new `access_token` row and Atlas consumes the
  # previous one (`refresh_token_revoked_at`) in the same transaction, so a
  # normal rotation always leaves exactly one active row. Revocation, an expired
  # refresh TTL, or a discarded client (no further rotations) ends the grant.
  # Boruta timestamps are timezone-less UTC wall time. The lookup is bounded by
  # the `(client_id, value)` unique index on `oauth_tokens`.
  defp active_grant do
    from t in "oauth_tokens",
      join: c in "oauth_clients",
      on: c.id == t.client_id,
      where: t.client_id == fragment("?::uuid", parent_as(:installation).oauth_client_id),
      where: t.sub == fragment("?::text", parent_as(:installation).user_id),
      where: t.type == "access_token" and not is_nil(t.refresh_token),
      where: is_nil(t.revoked_at) and is_nil(t.refresh_token_revoked_at),
      where:
        fragment(
          "? + (? * interval '1 second') > (statement_timestamp() AT TIME ZONE 'UTC')",
          t.inserted_at,
          c.refresh_token_ttl
        ),
      select: 1
  end

  # A transaction-scoped advisory lock serializes concurrent requests for the
  # same installation, including its very first insert.
  defp locked(installation_id, fun) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["push_installation:" <> installation_id])

      Installation
      |> where([i], i.installation_id == ^installation_id)
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> fun.()
    end)
  end

  defp upsert(%Installation{retired_at: %DateTime{}}, _user, _client_id, _installation_id, _attrs, _hash, _audit),
    do: {:error, :retired}

  defp upsert(%Installation{platform: platform}, _user, _client_id, _installation_id, %{platform: other}, _hash, _audit)
       when platform != other, do: {:error, :conflict}

  defp upsert(%Installation{user_id: user_id} = existing, %User{id: user_id} = user, client_id, _id, attrs, hash, audit) do
    save(existing, user, client_id, attrs, hash, audit)
  end

  defp upsert(%Installation{} = existing, _user, client_id, _installation_id, _attrs, hash, audit) do
    # Ownership never moves between users. When the same app installation
    # proves itself (same OAuth client or same device token), retire the
    # previous owner's row so its queued jobs die, then make the client rotate.
    if existing.oauth_client_id == client_id or existing.token_hash == hash do
      retire!(existing, "owner_changed", audit)
      {:error, :retired}
    else
      {:error, :conflict}
    end
  end

  defp upsert(nil, user, client_id, installation_id, attrs, hash, audit) do
    save(%Installation{installation_id: installation_id}, user, client_id, attrs, hash, audit)
  end

  defp save(installation, user, client_id, attrs, hash, audit) do
    now = DateTime.utc_now()

    # The same device token registered under another installation ID (reinstall
    # or restore) is one physical device: only the newest registration may own it.
    Installation
    |> where([i], i.token_hash == ^hash and is_nil(i.retired_at))
    |> where([i], i.installation_id != ^installation.installation_id)
    |> select([i], i)
    |> Repo.update_all(set: retired_fields("superseded"))
    |> elem(1)
    |> Enum.each(&audit_retired(&1, "superseded", audit))

    new? = is_nil(installation.id)
    token_changed? = installation.token_hash != hash

    installation
    |> Ecto.Changeset.change(%{
      user_id: user.id,
      oauth_client_id: client_id,
      platform: attrs.platform,
      environment: attrs.environment,
      token: attrs.token,
      token_hash: hash,
      token_updated_at: if(token_changed?, do: now, else: installation.token_updated_at),
      last_registered_at: now
    })
    |> Ecto.Changeset.unique_constraint(:installation_id, name: :push_installations_installation_id_index)
    |> Ecto.Changeset.unique_constraint(:token_hash, name: :push_installations_live_token_hash_index)
    |> Repo.insert_or_update()
    |> case do
      {:ok, saved} ->
        # Plain refreshes are not audited, to keep foreground re-registration quiet.
        if new? or token_changed? or installation.environment != saved.environment do
          Audit.record(
            "push_installation.registered",
            %{
              target_type: "push_installation",
              target_id: saved.id,
              metadata: %{
                "platform" => saved.platform,
                "environment" => saved.environment,
                "created" => new?,
                "token_rotated" => not new? and token_changed?
              }
            },
            audit
          )
        end

        evict_oldest!(user.id, audit)
        {:ok, saved}

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp evict_oldest!(user_id, audit) do
    keep =
      Installation
      |> where([i], i.user_id == ^user_id and is_nil(i.retired_at))
      |> order_by([i], desc: i.last_registered_at, desc: i.id)
      |> limit(@max_live_per_user)
      |> select([i], i.id)

    Installation
    |> where([i], i.user_id == ^user_id and is_nil(i.retired_at) and i.id not in subquery(keep))
    |> select([i], i)
    |> Repo.update_all(set: retired_fields("evicted"))
    |> elem(1)
    |> Enum.each(&audit_retired(&1, "evicted", audit))
  end

  defp retire!(installation, reason, audit) do
    retired =
      installation
      |> Ecto.Changeset.change(retired_fields(reason))
      |> Repo.update!()

    audit_retired(installation, reason, audit)
    retired
  end

  defp insert_tombstone!(installation_id, client_id, audit) do
    tombstone =
      Repo.insert!(%Installation{
        installation_id: installation_id,
        oauth_client_id: client_id,
        retired_at: DateTime.utc_now(),
        retired_reason: "unregistered"
      })

    audit_retired(tombstone, "unregistered", audit)
    :ok
  end

  defp audit_retired(installation, reason, audit) do
    Audit.record(
      "push_installation.retired",
      %{
        target_type: "push_installation",
        target_id: installation.id,
        metadata: %{"reason" => reason, "platform" => installation.platform}
      },
      audit
    )
  end

  defp audit_opts(user, opts), do: Keyword.merge([actor: user], opts)

  defp put_reason(metadata, nil), do: metadata
  defp put_reason(metadata, reason), do: Map.put(metadata, "reason", to_string(reason))

  defp retired_fields(reason) do
    [retired_at: DateTime.utc_now(), retired_reason: reason, user_id: nil, token: nil, token_hash: nil]
  end

  defp validate_installation_id(value) when is_binary(value) do
    if Regex.match?(@uuid, value), do: {:ok, value}, else: {:error, :invalid}
  end

  defp validate_installation_id(_value), do: {:error, :invalid}

  defp validate_device(params) do
    with true <- params |> Map.keys() |> Enum.sort() == Enum.sort(@body_keys),
         %{"platform" => platform, "token" => token, "environment" => environment}
         when is_binary(platform) and is_binary(token) and is_binary(environment) <- params,
         {:ok, token} <- validate_token(platform, token),
         true <- valid_environment?(platform, environment) do
      {:ok, %{platform: platform, token: token, environment: environment}}
    else
      _ -> {:error, :invalid}
    end
  end

  defp validate_token("ios", token) do
    if Regex.match?(@ios_token, token), do: {:ok, String.downcase(token)}, else: :error
  end

  defp validate_token("android", token) do
    if Regex.match?(@android_token, token), do: {:ok, token}, else: :error
  end

  defp validate_token(_platform, _token), do: :error

  defp valid_environment?("ios", environment), do: environment in ["sandbox", "production"]
  defp valid_environment?("android", environment), do: environment == "production"

  defp ensure_available(platform, environment) do
    if Config.available?(platform, environment), do: :ok, else: {:error, :unavailable}
  end

  defp valid_destination?({screen, nil}) when is_binary(screen), do: NativeLinks.for_open([screen]) == {screen, nil}

  defp valid_destination?({screen, record_id}) when is_binary(screen) and is_binary(record_id),
    do: NativeLinks.for_open([screen, record_id]) == {screen, record_id}

  defp valid_destination?(_destination), do: false
end
