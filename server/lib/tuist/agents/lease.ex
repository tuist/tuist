defmodule Tuist.Agents.Lease do
  @moduledoc """
  Which `agents` pod hosts a durable Condukt session.

  A row in `agent_sessions` per session holds its host and a lease that host
  renews. Each claim raises the session's `epoch`, which fences every write
  the session makes (`Tuist.Agents.SessionStore`) and every effect a feature
  fences on it, such as Threads' `owns_run?/2`. A host that loses its lease, by dying, by a
  partition, or by pausing past it, can no longer write, so a session has at
  most one writer however many pods believe they host it.

  A session wants a host from `want/2` until a host releases it as not
  wanted (`release/3`), typically once it has gone idle. While it wants one
  and no lease holds it, any host may `claim/2` it: there is no leader and
  no sweep, so a session whose host died is picked up as soon as its lease
  lapses.
  """

  import Ecto.Query

  alias Tuist.Repo

  @ttl_seconds 20
  @hosts_topic "agent_hosts"

  @doc "The PubSub topic runners listen on to claim without waiting for their poll."
  def hosts_topic, do: @hosts_topic

  def ttl_ms, do: @ttl_seconds * 1000

  @doc """
  Marks the session `id` of `kind` as wanting a host, creating its row. Call
  it inside the transaction that stores the work, so the work and the want
  commit together, and `wake/1` once it committed.

  `min_epoch:` raises the session's epoch to at least that value, so the
  next claim is later than work a feature fenced with an epoch of its own,
  such as a run an earlier release started. It never lowers it.
  """
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

  @doc """
  Claims up to `limit` sessions that want a host for `host`, longest waiting
  first. Returns `[%{id: id, kind: kind, epoch: epoch}]`.
  """
  def claim(_host, limit) when limit <= 0, do: []

  def claim(host, limit) do
    # SKIP LOCKED lets every host claim at once without waiting on another's
    # rows; the lease check in the same statement keeps a held session held.
    # The candidates are locked once in a materialized CTE: a LIMIT subquery
    # joined into the UPDATE may be executed again, as the inner side of a
    # nested loop, and with SKIP LOCKED each pass can pick other rows, so a
    # host would claim more sessions than it has room for.
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

  @doc """
  Renews the leases `host` holds on `leases` (`[{id, epoch}]`). Returns the
  ones it still holds with their want counts, `%{{id, epoch} => want_seq}`;
  the host must stop hosting the others at once. Pass a want count to
  `release/3` to release an idle session only if no want arrived since.
  """
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
  Hands a session back. By default it still wants a host, as when a pod
  drains for a deploy: another host claims it at once and resumes its run.
  With `delay_ms:` it wants one but no host claims it until then, as when it
  could not reach its store; a `want/2` meanwhile makes it claimable at once.
  With `wanted: false` it wants none until the next `want/2`, as when it
  went idle; pass `seen:`, the want count read before the session was found
  idle, and a want stored after that read keeps it wanted. Counting rather
  than comparing times makes this exact: the want's row lock orders it.
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
              wanted_at: fragment("CURRENT_TIMESTAMP + make_interval(secs => ?)", ^(delay_ms / 1000))
            ]
          )

        wanted? ->
          update(query, set: [host: nil, lease_expires_at: nil])

        true ->
          # Only the wants seen before the session went idle are spent; a later
          # one, such as a message that raced the stop, keeps it wanted.
          if is_nil(seen),
            do: update(query, set: [host: nil, lease_expires_at: nil, wanted: false]),
            else: update(query, [s], set: [host: nil, lease_expires_at: nil, wanted: s.want_seq != ^seen])
      end

    {count, _} = Repo.update_all(query, [], log: false)

    # Wakes hosts for a handed-off session, or for one a racing want kept. A
    # delayed one is found by their poll once its delay passed.
    if count == 1 and delay_ms == 0, do: notify()
    :ok
  end

  @doc "The PubSub topic a hosted session's process listens on for `wake/1`."
  def topic(id), do: "agent_session:" <> id

  @doc """
  Tells the session's process, wherever it is hosted, that it has new work,
  and runners that a session may want a host. Call it after the transaction
  that stored the work commits. Runners also poll, so a lost wake only delays.
  """
  def wake(id) do
    Phoenix.PubSub.broadcast(Tuist.PubSub, topic(id), {__MODULE__, :wake})
    notify()
  end

  @doc "Tells runners that a session wants a host, so they need not wait for their next poll."
  def notify do
    Phoenix.PubSub.broadcast(Tuist.PubSub, @hosts_topic, {__MODULE__, :claimable})
  end
end
