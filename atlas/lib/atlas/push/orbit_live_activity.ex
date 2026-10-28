defmodule Atlas.Push.OrbitLiveActivity do
  @moduledoc """
  Aggregate Pip Live Activities with bounded conversation titles. No inference or channel is kept
  alive for delivery. Jobs carry only the registration ID and always recompute
  committed, currently authorized state. See push/AGENTS.md for lifecycle fences.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Orbit.Message
  alias Atlas.Orbit.Participant
  alias Atlas.Orbit.Run
  alias Atlas.Orbit.Thread
  alias Atlas.Push.APNs
  alias Atlas.Push.Config
  alias Atlas.Push.LiveActivity
  alias Atlas.Push.Workers.UpdateLiveActivity
  alias Atlas.Repo
  alias Atlas.Users
  alias Atlas.Users.User

  require Logger

  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  @token ~r/\A(?:[0-9a-fA-F]{2}){16,256}\z/
  @lifetime 8 * 60 * 60
  @batch 100
  @heartbeat 60

  def snapshot(%User{} = user) do
    %{available: Config.available?("ios"), content: content(user)}
  end

  def content(%User{} = user) do
    scopes = Users.scopes_for(user)

    eligible =
      from run in Run,
        join: thread in Thread,
        on: thread.id == run.thread_id,
        join: participant in Participant,
        on: participant.thread_id == thread.id,
        where: participant.user_id == ^user.id,
        where: run.acting_user_id == ^user.id,
        where: run.status in ["queued", "running"],
        where: is_nil(run.cancel_requested_at),
        where: thread.status == "active",
        where: fragment("?::text[] <@ ?::text[]", thread.required_scopes, type(^scopes, {:array, :string}))

    runs =
      Repo.all(
        from [run, thread] in eligible,
          order_by: [asc: fragment("COALESCE(?, ?)", run.started_at, run.inserted_at), asc: run.id],
          limit: 3,
          select: %{
            run_id: run.id,
            id: thread.id,
            title: thread.title,
            status: run.status,
            activity: run.activity,
            active_count: fragment("count(*) OVER ()"),
            started_at: type(fragment("COALESCE(?, ?)", run.started_at, run.inserted_at), :utc_datetime_usec)
          }
      )

    run_ids = Enum.map(runs, & &1.run_id)

    tools =
      Repo.all(
        from message in Message,
          where: message.run_id in ^run_ids and message.kind == "tool",
          group_by: message.run_id,
          select:
            {message.run_id,
             %{
               completed: filter(count(message.id), message.tool_status in ["succeeded", "failed"]),
               running: filter(count(message.id), message.tool_status == "running")
             }}
      )
      |> Map.new()

    conversations =
      Enum.map(runs, fn run ->
        steps = Map.get(tools, run.run_id, %{completed: 0, running: 0})

        status =
          cond do
            run.status == "queued" -> "queued"
            run.activity == "compacting" -> "compacting"
            steps.running > 0 -> "using_tools"
            true -> "running"
          end

        %{
          id: run.id,
          title: activity_title(run.title),
          status: status,
          started_at: DateTime.to_unix(run.started_at),
          completed_steps: steps.completed
        }
      end)

    count =
      case runs do
        [first | _] -> first.active_count
        [] -> 0
      end

    %{active_count: count, conversations: conversations, updated_at: DateTime.to_unix(DateTime.utc_now())}
  end

  defp activity_title(title) do
    title =
      title
      |> String.replace(~r/[\s\p{Z}\p{Cc}\p{Cf}]+/u, " ")
      |> String.trim()
      |> String.codepoints()
      |> Enum.take(80)
      |> Enum.join()
      |> String.trim()

    if title == "", do: "Conversation", else: title
  end

  def register(%User{} = user, client_id, id, params) do
    with :ok <- valid_id(id),
         {:ok, token, environment} <- validate(params),
         true <- Config.available?("ios", environment) do
      locked(
        id,
        fn existing ->
          cond do
            existing && existing.retired_at ->
              {:error, :retired}

            existing && not owned_by?(existing, user, client_id) ->
              {:error, :conflict}

            not active_grant?(user.id, client_id) ->
              {:error, :session_ended}

            existing && DateTime.compare(existing.expires_at, DateTime.utc_now()) != :gt ->
              retire!(existing)
              enqueue(id)
              {:error, :retired}

            true ->
              save(existing, user, client_id, id, token, environment)
          end
        end,
        user.id
      )
    else
      false -> {:error, :unavailable}
      error -> error
    end
  end

  def unregister(%User{} = user, client_id, id) do
    with :ok <- valid_id(id) do
      locked(id, fn
        nil ->
          Repo.insert!(%LiveActivity{
            id: id,
            oauth_client_id: client_id,
            retired_at: DateTime.utc_now(),
            reconciled_at: DateTime.utc_now()
          })

          audit(id, "retired", user.id)
          :ok

        registration ->
          if owned_by?(registration, user, client_id) do
            retire!(registration)
            enqueue(id)
            audit(id, "retired", user.id)
          end

          :ok
      end)
    end
  end

  defp save(existing, user, client_id, id, token, environment) do
    # A client runs one aggregate activity. A new local activity ends its old
    # registration; neither a new user nor a different client can take it over.
    live = from r in LiveActivity, where: r.user_id == ^user.id, where: is_nil(r.retired_at)

    Repo.all(from r in live, where: r.oauth_client_id == ^client_id, where: r.id != ^id)
    |> Enum.each(fn old ->
      retire!(old)
      enqueue(old.id)
    end)

    if Repo.aggregate(from(r in live, where: r.id != ^id), :count) >= 10, do: Repo.rollback(:conflict)

    now = DateTime.utc_now()

    registration =
      existing ||
        %LiveActivity{
          id: id,
          user_id: user.id,
          oauth_client_id: client_id,
          expires_at: DateTime.add(now, @lifetime),
          reconciled_at: now,
          inserted_at: now
        }

    changes = %{token: token, token_hash: :crypto.hash(:sha256, token), environment: environment}
    rotated? = registration.token != token or registration.environment != environment

    changes =
      if rotated?,
        do: Map.put(changes, :last_fingerprint, nil),
        else: changes

    saved =
      registration
      |> Ecto.Changeset.change(changes)
      |> Ecto.Changeset.unique_constraint(:token_hash)
      |> Ecto.Changeset.unique_constraint(:user_id, name: :orbit_live_activities_user_id_oauth_client_id_index)
      |> Repo.insert_or_update()

    case saved do
      {:ok, row} ->
        enqueue(row.id)
        if rotated?, do: audit(id, "registered", user.id)
        :ok

      {:error, _changeset} ->
        Repo.rollback(:conflict)
    end
  end

  @doc "Best-effort wakeup from committed id-only Orbit invalidations, on every replica."
  def thread_changed(thread_id) do
    actors = from run in Run, where: run.thread_id == ^thread_id, select: run.acting_user_id

    from(r in LiveActivity, where: r.user_id in subquery(actors) and not is_nil(r.token), select: r.id)
    |> Repo.all()
    |> Enum.each(&enqueue/1)

    :ok
  rescue
    _ -> Logger.warning("orbit live activity wakeup failed: enqueue_error")
  end

  @doc "Bounded round-robin reconciliation covers missed notifications and authorization changes."
  def reconcile do
    Repo.transaction(fn ->
      registrations =
        Repo.all(
          from r in LiveActivity,
            where: not is_nil(r.token),
            order_by: [asc: r.reconciled_at, asc: r.id],
            limit: @batch,
            lock: "FOR UPDATE SKIP LOCKED"
        )

      Enum.each(registrations, fn registration ->
        registration |> Ecto.Changeset.change(reconciled_at: DateTime.utc_now()) |> Repo.update!()
        enqueue(registration.id)
      end)

      length(registrations)
    end)
  rescue
    _ -> {:error, :reconciliation_failed}
  end

  def prune do
    # Keep tombstones longer than any access/refresh request can remain useful.
    cutoff = DateTime.add(DateTime.utc_now(), -180, :day)
    Repo.delete_all(from r in LiveActivity, where: r.retired_at < ^cutoff and is_nil(r.token))
    :ok
  end

  defp enqueue(id) do
    %{registration_id: id}
    |> UpdateLiveActivity.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, _reason} -> Repo.rollback(:enqueue_failed)
    end
  end

  @doc "Serializes provider sends per registration and recomputes state, never replaying a callback's snapshot."
  def deliver(id, last_attempt? \\ false) do
    with :ok <- valid_id(id) do
      locked(id, fn
        %LiveActivity{token: token} = registration when is_binary(token) -> deliver_locked(registration, last_attempt?)
        _ -> :ok
      end)
    end
  end

  defp deliver_locked(registration, last_attempt?) do
    now = DateTime.utc_now()
    content = current_content(registration, now)
    ending? = content.active_count == 0
    registration = if ending?, do: retire!(registration), else: registration
    event = if ending?, do: "end", else: "update"

    fingerprint =
      :crypto.hash(:sha256, :erlang.term_to_binary({event, Map.delete(content, :updated_at)}, [:deterministic]))

    timestamp = content.updated_at

    cond do
      ending? and DateTime.diff(now, registration.retired_at) >= 120 ->
        drop!(registration)
        {:cancel, :end_expired}

      unchanged?(registration, fingerprint, now, ending?) ->
        :ok

      registration.last_timestamp && timestamp <= registration.last_timestamp ->
        {:snooze, 1}

      true ->
        send_payload(registration, content, event, fingerprint, now, last_attempt?)
    end
  end

  defp current_content(registration, now) do
    user = registration.user_id && Repo.get(User, registration.user_id)
    if live_session?(registration, user, now), do: content(user), else: empty_content()
  end

  defp live_session?(registration, %User{} = user, now) do
    is_nil(registration.retired_at) and DateTime.before?(now, registration.expires_at) and
      active_grant?(user.id, registration.oauth_client_id)
  end

  defp live_session?(_registration, _user, _now), do: false

  defp unchanged?(registration, fingerprint, now, ending?) do
    not ending? and registration.last_fingerprint == fingerprint and not is_nil(registration.last_sent_at) and
      DateTime.diff(now, registration.last_sent_at) < @heartbeat
  end

  defp send_payload(registration, content, event, fingerprint, now, last_attempt?) do
    timestamp = content.updated_at
    ending? = event == "end"
    expires_at = delivery_expiry(registration, now)

    aps = %{
      "timestamp" => timestamp,
      "event" => event,
      "content-state" => content,
      "stale-date" => DateTime.to_unix(expires_at)
    }

    aps = if ending?, do: Map.put(aps, "dismissal-date", timestamp), else: aps
    payload = %{"aps" => aps}

    if byte_size(JSON.encode!(payload)) >= 4096 do
      {:cancel, :payload_too_large}
    else
      APNs.deliver(registration, payload,
        live_activity: true,
        expires_at: expires_at,
        collapse_id: registration.id
      )
      |> delivered(registration, fingerprint, timestamp, ending?, last_attempt?)
    end
  end

  defp delivery_expiry(%LiveActivity{retired_at: %DateTime{} = at}, _now), do: DateTime.add(at, 120)

  defp delivery_expiry(registration, now) do
    deadline = DateTime.add(now, 120)
    if DateTime.before?(registration.expires_at, deadline), do: registration.expires_at, else: deadline
  end

  defp delivered(:ok, registration, fingerprint, timestamp, ending?, _last?) do
    registration
    |> Ecto.Changeset.change(last_fingerprint: fingerprint, last_timestamp: timestamp, last_sent_at: DateTime.utc_now())
    |> Repo.update!()
    |> then(fn row -> if ending?, do: drop!(row) end)

    audit(registration.id, if(ending?, do: "ended", else: "updated"))
    :ok
  end

  defp delivered({:invalid_token, _opts}, registration, _fingerprint, _timestamp, _ending?, _last?) do
    # Rotation and sends hold the same row lock: this is still the rejected token.
    registration |> retire!() |> drop!()
    audit(registration.id, "invalidated")
    {:cancel, :token_invalidated}
  end

  defp delivered({:retry, seconds}, registration, _fingerprint, _timestamp, ending?, last?) do
    if ending? and (last? or DateTime.diff(DateTime.utc_now(), registration.retired_at) >= 120) do
      drop!(registration)
      {:cancel, :end_expired}
    else
      limit = if ending?, do: max(1, 120 - DateTime.diff(DateTime.utc_now(), registration.retired_at)), else: 3600
      if is_integer(seconds), do: {:snooze, min(max(seconds, 1), limit)}, else: {:error, :provider_unavailable}
    end
  end

  defp delivered({:error, reason}, registration, _fingerprint, _timestamp, ending?, _last?) do
    if ending?, do: drop!(registration)
    {:cancel, reason}
  end

  defp empty_content, do: %{active_count: 0, conversations: [], updated_at: DateTime.to_unix(DateTime.utc_now())}

  defp retire!(%LiveActivity{retired_at: nil} = row),
    do: row |> Ecto.Changeset.change(retired_at: DateTime.utc_now()) |> Repo.update!()

  defp retire!(row), do: row

  defp drop!(row),
    do: row |> Ecto.Changeset.change(token: nil, token_hash: nil, user_id: nil, last_fingerprint: nil) |> Repo.update!()

  defp owned_by?(registration, user, client_id),
    do: registration.user_id == user.id and registration.oauth_client_id == client_id

  defp active_grant?(user_id, client_id) do
    # Same active refresh-grant fence as Push, plus the native redirect shape.
    Repo.exists?(
      from t in "oauth_tokens",
        join: c in "oauth_clients",
        on: c.id == t.client_id,
        where: t.client_id == type(^client_id, Ecto.UUID) and t.sub == ^user_id,
        where: c.redirect_uris == ^["dev.tuist.atlas://oauth-callback"],
        where: t.type == "access_token" and not is_nil(t.refresh_token),
        where: is_nil(t.revoked_at) and is_nil(t.refresh_token_revoked_at),
        where:
          fragment(
            "? + (? * interval '1 second') > (statement_timestamp() AT TIME ZONE 'UTC')",
            t.inserted_at,
            c.refresh_token_ttl
          )
    )
  end

  defp locked(id, fun, user_id \\ nil) do
    Repo.transaction(fn ->
      if user_id do
        Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["orbit_live_user:" <> user_id])
      end

      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["orbit_live_activity:" <> id])
      fun.(Repo.one(from r in LiveActivity, where: r.id == ^id, lock: "FOR UPDATE"))
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp valid_id(id) when is_binary(id), do: if(Regex.match?(@uuid, id), do: :ok, else: {:error, :invalid})
  defp valid_id(_id), do: {:error, :invalid}

  defp validate(%{"token" => token, "environment" => environment} = params)
       when map_size(params) == 2 and is_binary(token) and environment in ["sandbox", "production"] do
    if Regex.match?(@token, token), do: {:ok, String.downcase(token), environment}, else: {:error, :invalid}
  end

  defp validate(_params), do: {:error, :invalid}

  defp audit(id, outcome, actor_id \\ nil) do
    Audit.record(
      "orbit_live_activity." <> outcome,
      %{target_type: "orbit_live_activity", target_id: id},
      actor_id: actor_id,
      interface: if(actor_id, do: "api", else: "worker")
    )
  end
end
