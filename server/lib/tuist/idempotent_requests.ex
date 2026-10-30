defmodule Tuist.IdempotentRequests do
  @moduledoc """
  Deduplicates report-creation requests that carry a client-supplied id.

  Clients retry a request whose response was lost. Reports are written to
  ClickHouse through buffers and into tables that don't deduplicate, so the
  write path can't tell a retry from a new report. Before creating anything, a
  request claims `(project_id, kind, request_id)` in PostgreSQL, which is atomic
  across replicas:

    * The request that inserts the claim runs the creation and records its
      result on the claim.
    * A request finding a completed claim gets the recorded result back as
      `{:replayed, result}` without creating anything.
    * A request finding a claim still being processed waits for it, up to the
      `:wait_timeout` option, and otherwise returns `{:error, :in_progress}`.
    * A creation that fails or raises releases its claim, so a retry can create
      the report. A claim whose holder disappeared (for example, a replica that
      was killed mid-request) is taken over once its lease expires. Only the
      current lease holder can complete or release a claim.

  Requests without an id, or whose id isn't a UUID, run the creation without a
  claim. Claims are deleted
  an hour after they were taken by `Workers.PruneWorker`.
  """

  import Ecto.Query

  alias Tuist.IdempotentRequests.Claim
  alias Tuist.Repo

  @lease_seconds 300
  @retention_seconds 3_600
  @wait_timeout_ms 10_000
  @poll_interval_ms 200
  @prune_batch_size 5_000

  @doc """
  Runs `create` once per `(kind, project_id, request_id)`.

  `create` returns `{:ok, result}` when the report was created, and the result
  is recorded for replays. Any other value releases the claim and is returned
  as is. Results must be plain terms (maps, lists, strings, numbers, atoms and
  date/time structs), since they're serialized with `:erlang.term_to_binary/2`.

  Returns `{:ok, result}` for a new creation, `{:replayed, result}` for a
  request that was already processed, `{:error, :in_progress}` when another
  request with the same id is still being processed after the wait, or the
  value `create` returned otherwise.
  """
  def run(kind, project_id, request_id, create, opts \\ [])

  def run(_kind, _project_id, nil, create, _opts), do: create.()

  def run(kind, project_id, request_id, create, opts) when is_binary(kind) do
    case Ecto.UUID.cast(request_id) do
      {:ok, request_id} ->
        key = %{project_id: project_id, kind: kind, request_id: request_id}
        deadline = System.monotonic_time(:millisecond) + Keyword.get(opts, :wait_timeout, @wait_timeout_ms)
        claim(key, create, deadline)

      :error ->
        create.()
    end
  end

  @doc """
  Replaces the recorded result of a completed request.
  """
  def update_result(kind, project_id, request_id, result) do
    {count, _} =
      Repo.update_all(
        from(claim in key_query(%{project_id: project_id, kind: kind, request_id: request_id}),
          where: not is_nil(claim.completed_at)
        ),
        set: [result: encode(result), updated_at: now()]
      )

    if count == 1, do: :ok, else: {:error, :not_found}
  end

  @doc """
  Deletes claims taken more than the retention period ago, up to a batch.
  Returns how many were deleted.
  """
  def prune do
    cutoff = DateTime.add(now(), -@retention_seconds, :second)

    expired =
      from(claim in Claim,
        where: claim.claimed_at < ^cutoff,
        select: %{project_id: claim.project_id, kind: claim.kind, request_id: claim.request_id},
        limit: @prune_batch_size
      )

    {deleted, _} =
      Repo.delete_all(
        from(claim in Claim,
          join: expired in subquery(expired),
          on:
            claim.project_id == expired.project_id and claim.kind == expired.kind and
              claim.request_id == expired.request_id
        )
      )

    deleted
  end

  def prune_batch_size, do: @prune_batch_size

  defp claim(key, create, deadline) do
    lease_id = Ecto.UUID.generate()
    now = now()

    {inserted, _} =
      Repo.insert_all(
        Claim,
        [Map.merge(key, %{lease_id: lease_id, claimed_at: now, inserted_at: now, updated_at: now})],
        on_conflict: :nothing,
        conflict_target: [:project_id, :kind, :request_id]
      )

    if inserted == 1 do
      execute(key, lease_id, create)
    else
      case Repo.one(key_query(key)) do
        nil ->
          claim(key, create, deadline)

        %Claim{completed_at: %DateTime{}, result: result} ->
          {:replayed, decode(result)}

        %Claim{} = claim ->
          if DateTime.diff(now, claim.claimed_at, :second) >= @lease_seconds do
            take_over(key, claim, create, deadline)
          else
            wait(key, create, deadline)
          end
      end
    end
  end

  defp take_over(key, %Claim{lease_id: expired_lease_id}, create, deadline) do
    lease_id = Ecto.UUID.generate()
    now = now()

    {count, _} =
      Repo.update_all(
        from(claim in key_query(key),
          where: claim.lease_id == ^expired_lease_id and is_nil(claim.completed_at)
        ),
        set: [lease_id: lease_id, claimed_at: now, updated_at: now]
      )

    if count == 1, do: execute(key, lease_id, create), else: claim(key, create, deadline)
  end

  defp wait(key, create, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :in_progress}
    else
      Process.sleep(@poll_interval_ms)
      claim(key, create, deadline)
    end
  end

  defp execute(key, lease_id, create) do
    case create_releasing_on_failure(key, lease_id, create) do
      {:ok, result} = created ->
        Repo.update_all(
          from(claim in key_query(key), where: claim.lease_id == ^lease_id),
          set: [completed_at: now(), result: encode(result), updated_at: now()]
        )

        created

      other ->
        other
    end
  end

  defp create_releasing_on_failure(key, lease_id, create) do
    case create.() do
      {:ok, _result} = created ->
        created

      other ->
        release(key, lease_id)
        other
    end
  catch
    kind, reason ->
      release(key, lease_id)
      :erlang.raise(kind, reason, __STACKTRACE__)
  end

  defp release(key, lease_id) do
    Repo.delete_all(from(claim in key_query(key), where: claim.lease_id == ^lease_id and is_nil(claim.completed_at)))
  end

  defp key_query(%{project_id: project_id, kind: kind, request_id: request_id}) do
    from(claim in Claim,
      where: claim.project_id == ^project_id and claim.kind == ^kind and claim.request_id == ^request_id
    )
  end

  defp encode(result), do: :erlang.term_to_binary(result, [:compressed])

  defp decode(result), do: :erlang.binary_to_term(result, [:safe])

  defp now, do: DateTime.truncate(Tuist.Time.utc_now(), :second)
end
