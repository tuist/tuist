defmodule Tuist.Runners.SessionReplication do
  @moduledoc """
  Replicates Postgres `runner_sessions` into the ClickHouse
  `runner_concurrency_sessions` table that the Concurrency card reads.

  ## Why a tailer rather than an outbox

  `runner_jobs` is fed by a transition outbox because its writers need
  the ClickHouse row to move in lockstep with a guarded lifecycle
  transition. Sessions have no such contract: the replica is a
  read-model for one chart, and every mutation on `runner_sessions`
  bumps `updated_at`. Tailing that column gets the same at-least-once
  delivery without a second write path through the session lifecycle,
  and without an outbox table to drain.

  It also makes the initial load fall out for free. There is no cursor
  to seed: the resume point is `max(source_updated_at)` in ClickHouse,
  so an empty replica walks the whole of `runner_sessions` from the
  beginning over successive ticks and then settles into tailing.

  ## Why re-reading is safe here

  Reading Postgres and stamping `ingested_at` with the current time is
  the safe direction: a later ingest saw a fresher authoritative row,
  so letting it win the version comparison is always right. The inverse
  — reading the ClickHouse row and carrying it forward — is what left
  `runner_jobs` with rows stuck non-terminal.

  `@overlap_seconds` re-reads a window either side of the resume point.
  `runner_sessions.updated_at` is second-truncated and a transaction
  can commit after one stamped later, so a strict `>` cursor can skip a
  row. Re-reading costs nothing: the replayed row carries the same
  content under a newer `ingested_at`.

  The resume point is resolved once per drain, in `start_cursor/0`, and
  pages advance on `(updated_at, id)` from there. Re-deriving it per
  batch instead would stall the tailer outright: a drain only continues
  while batches come back full, and if the overlap window held a full
  batch, every batch would re-select the same first rows and nothing
  newer would ever replicate.

  ## What is resolved here rather than at read time

  The platform and machine shape, via `Catalog`, because sessions
  predating those columns fall back to matching the fleet name against
  configured prefixes — Elixir's job, not a query's. And the release
  moment, because it depends on `runner_job_completions`, which lives
  in Postgres. Changing either rule means re-ingesting: truncate the
  replica and the tailer rebuilds it.

  `released_at` is never null. Postgres `LEAST` skips nulls, so a
  session with nothing recorded resolves to the runner-session ceiling
  on its own, and the reader needs no open-session branch: an open
  session simply cannot be shown holding its slot past that bound.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Repo
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.ConcurrencySession
  alias Tuist.Runners.JobCompletion
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.RunnerSessions

  @platforms [:linux, :macos]
  @batch_size 5_000
  @overlap_seconds 120

  @doc """
  Where a drain starts: the resume point, paired with an id below every
  row's so the first page covers the whole overlap window.
  """
  def start_cursor, do: {resume_point(), 0}

  @doc """
  Copies one batch of sessions across, returning `{:ok, count, cursor}`
  for the caller to page from.

  A batch of `@batch_size` means there is more to do, so the caller
  loops rather than waiting for the next tick — that is what lets an
  empty replica catch up on history at more than one batch a minute.
  """
  def replicate_batch({%DateTime{} = since, after_id}) do
    sessions =
      Repo.all(
        from(session in RunnerSession,
          left_join: completion in JobCompletion,
          on:
            is_nil(session.job_ended_at) and
              completion.workflow_job_id ==
                coalesce(session.executed_workflow_job_id, session.workflow_job_id),
          where:
            fragment(
              "(?, ?) > (?, ?)",
              session.updated_at,
              session.id,
              ^DateTime.truncate(since, :second),
              ^after_id
            ),
          order_by: [asc: session.updated_at, asc: session.id],
          limit: @batch_size,
          select: %{
            id: session.id,
            account_id: session.account_id,
            platform: session.platform,
            fleet_name: session.fleet_name,
            vcpus: session.vcpus,
            memory_gb: session.memory_gb,
            started_at: session.started_at,
            updated_at: session.updated_at,
            released_at:
              fragment(
                "GREATEST(?, LEAST(COALESCE(?, ?, ?), ?, ? + make_interval(secs => ?)))",
                session.started_at,
                session.job_ended_at,
                completion.completed_at,
                session.ended_at,
                session.ended_at,
                session.started_at,
                ^RunnerSessions.max_session_lifetime_seconds()
              )
          }
        )
      )

    rows = sessions |> Enum.map(&replica_row/1) |> Enum.reject(&is_nil/1)

    if rows != [], do: IngestRepo.insert_all(ConcurrencySession, rows)

    {:ok, length(sessions), next_cursor(sessions, {since, after_id})}
  end

  # A page that resolved to no replica rows still has to advance the
  # cursor, or a batch of sessions on retired fleets would be re-read
  # forever.
  defp next_cursor([], cursor), do: cursor

  defp next_cursor(sessions, _cursor) do
    last = List.last(sessions)
    {last.updated_at, last.id}
  end

  @doc """
  Whether a batch of this size means more rows are waiting.
  """
  def full_batch?(count), do: count >= @batch_size

  @doc """
  Rows copied per batch.
  """
  def batch_size, do: @batch_size

  # The replica's own high-water mark, walked back by the overlap so a
  # row that committed late is picked up rather than skipped.
  defp resume_point do
    case ClickHouseRepo.one(from(s in ConcurrencySession, select: max(s.source_updated_at))) do
      nil -> ~U[1970-01-01 00:00:00.000000Z]
      %NaiveDateTime{} = naive -> naive |> DateTime.from_naive!("Etc/UTC") |> walk_back()
      %DateTime{} = datetime -> walk_back(datetime)
    end
  end

  defp walk_back(datetime), do: DateTime.add(datetime, -@overlap_seconds, :second)

  # `runner_sessions.updated_at` is second-precision and the replica
  # column is `DateTime64(6)`, so each side is widened or truncated at
  # the boundary rather than assumed compatible.

  # A session whose fleet resolves to no known platform is skipped
  # rather than charted under a guess. That is the retired-pool case,
  # and it is the only reason a row is dropped.
  defp replica_row(session) do
    case session_shape(session) do
      {:ok, resources} ->
        %{
          id: session.id,
          account_id: session.account_id,
          platform: Atom.to_string(resources.platform),
          vcpus: resources.vcpus,
          memory_gb: resources.memory_gb,
          started_at: session.started_at,
          released_at: session.released_at,
          source_updated_at: DateTime.add(session.updated_at, 0, :microsecond),
          ingested_at: DateTime.utc_now()
        }

      {:error, _reason} ->
        nil
    end
  end

  # Same resolution order admission uses for a claim in `Claims`: the
  # shape frozen on the row when it has one, the fleet's configured
  # shape otherwise, so a session predating the resource columns is
  # charted at what it reserved.
  defp session_shape(%{platform: platform, vcpus: vcpus, memory_gb: memory_gb})
       when platform in @platforms and is_integer(vcpus) and is_integer(memory_gb) and vcpus > 0 and memory_gb > 0 do
    {:ok, %{platform: platform, vcpus: vcpus, memory_gb: memory_gb}}
  end

  defp session_shape(%{fleet_name: fleet_name}) when is_binary(fleet_name) do
    Catalog.resources_for_fleet(fleet_name)
  end

  defp session_shape(_session), do: {:error, :invalid_resources}
end
