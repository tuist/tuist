defmodule LuftServer.Agents.Lease do
  @moduledoc """
  PostgreSQL-authoritative leases for durable agent sessions. Each claim raises
  the epoch used to fence journal writes and feature effects. Wants are counted
  so an idle release cannot discard work arriving after the idle check.
  """
  import Ecto.Query

  alias LuftServer.Repo

  @ttl_seconds 20
  @hosts_topic "agent_hosts"

  def hosts_topic, do: @hosts_topic
  def ttl_ms, do: @ttl_seconds * 1000

  @doc "Store inside the work transaction; call `wake/1` after commit."
  def want(id, kind, opts \\ []) do
    Repo.query!(
      """
      INSERT INTO agent_sessions AS s (id, kind, wanted, wanted_at, want_seq, epoch, inserted_at, updated_at)
      VALUES ($1, $2, true, CURRENT_TIMESTAMP, 1, $3, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      ON CONFLICT (id) DO UPDATE
      SET wanted = true, wanted_at = EXCLUDED.wanted_at, want_seq = s.want_seq + 1,
          epoch = GREATEST(s.epoch, EXCLUDED.epoch), updated_at = CURRENT_TIMESTAMP
      """,
      [id, kind, Keyword.get(opts, :min_epoch, 0)],
      log: false
    )

    :ok
  end

  def claim(_host, limit) when limit <= 0, do: []

  def claim(host, limit) do
    # Materialize once: a nested-loop UPDATE must not reevaluate a LIMIT with
    # SKIP LOCKED and claim more rows than this host has capacity for.
    %{rows: rows} =
      Repo.query!(
        """
        WITH free AS MATERIALIZED (
          SELECT id FROM agent_sessions
          WHERE wanted AND wanted_at <= CURRENT_TIMESTAMP AND deleted_at IS NULL
            AND (lease_expires_at IS NULL OR lease_expires_at < CURRENT_TIMESTAMP)
          ORDER BY wanted_at
          LIMIT $2
          FOR UPDATE SKIP LOCKED
        )
        UPDATE agent_sessions AS s
        SET epoch = s.epoch + 1, host = $1,
            lease_expires_at = CURRENT_TIMESTAMP + make_interval(secs => $3),
            updated_at = CURRENT_TIMESTAMP
        FROM free
        WHERE s.id = free.id
        RETURNING s.id, s.kind, s.epoch
        """,
        [host, limit, @ttl_seconds],
        log: false
      )

    Enum.map(rows, fn [id, kind, epoch] -> %{id: id, kind: kind, epoch: epoch} end)
  end

  @doc "Returns `%{{id, epoch} => want_seq}` for leases still held."
  def renew(_host, []), do: %{}

  def renew(host, leases) do
    ids = Enum.map(leases, &elem(&1, 0))

    %{rows: rows} =
      Repo.query!(
        """
        UPDATE agent_sessions
        SET lease_expires_at = CURRENT_TIMESTAMP + make_interval(secs => $3)
        WHERE host = $1 AND id = ANY($2) AND lease_expires_at > CURRENT_TIMESTAMP
        RETURNING id, epoch, want_seq
        """,
        [host, ids, @ttl_seconds],
        log: false
      )

    held = Map.new(rows, fn [id, epoch, seq] -> {{id, epoch}, seq} end)
    Map.take(held, leases)
  end

  @doc """
  Releases an epoch, wanted by default for handoff. `delay_ms:` delays retry;
  a new want overrides it. `wanted: false, seen: seq` spends only observed wants.
  """
  def release(id, epoch, opts \\ []) do
    wanted? = Keyword.get(opts, :wanted, true)
    seen = Keyword.get(opts, :seen)
    delay_ms = Keyword.get(opts, :delay_ms, 0)
    query = from(s in "agent_sessions", where: s.id == ^id and s.epoch == ^epoch)

    query =
      cond do
        wanted? and delay_ms > 0 ->
          update(query,
            set: [
              host: nil,
              lease_expires_at: nil,
              wanted_at:
                fragment("CURRENT_TIMESTAMP + make_interval(secs => ?)", ^(delay_ms / 1000))
            ]
          )

        wanted? ->
          update(query, set: [host: nil, lease_expires_at: nil])

        true ->
          if is_nil(seen),
            do: update(query, set: [host: nil, lease_expires_at: nil, wanted: false]),
            else:
              update(query, [s],
                set: [host: nil, lease_expires_at: nil, wanted: s.want_seq != ^seen]
              )
      end

    {count, _} = Repo.update_all(query, [], log: false)
    if count == 1 and delay_ms == 0, do: notify()
    :ok
  end

  def topic(id), do: "agent_session:" <> id

  def wake(id) do
    Phoenix.PubSub.broadcast(LuftServer.PubSub, topic(id), {__MODULE__, :wake})
    notify()
  end

  def notify do
    Phoenix.PubSub.broadcast(LuftServer.PubSub, @hosts_topic, {__MODULE__, :claimable})
  end
end
