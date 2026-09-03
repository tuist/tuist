defmodule Tuist.Bazel do
  @moduledoc false

  import Ecto.Query

  alias Tuist.Bazel.Invocation
  alias Tuist.ClickHouseFlop
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.ReapiCache

  def create_invocations([]), do: {0, nil}

  def create_invocations(invocations) when is_list(invocations) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    entries =
      Enum.map(invocations, fn invocation ->
        %{
          id: UUIDv7.generate(),
          invocation_id: invocation.invocation_id,
          command: invocation.command,
          status: invocation.status,
          exit_code: invocation.exit_code,
          started_at: invocation.started_at,
          finished_at: invocation.finished_at,
          duration_ms: invocation.duration_ms,
          project_id: invocation.project_id,
          account_handle: invocation.account_handle,
          project_handle: invocation.project_handle,
          cache_endpoint: invocation.cache_endpoint,
          inserted_at: now
        }
      end)

    IngestRepo.insert_all(Invocation, entries)
  end

  def list_invocations(project_id, flop_params \\ %{}) do
    {invocations, meta} =
      from(invocation in Invocation, hints: ["FINAL"])
      |> where([invocation], invocation.project_id == ^project_id)
      |> ClickHouseFlop.validate_and_run!(flop_params, for: Invocation)

    with_cache_summaries(project_id, invocations, meta)
  end

  def get_invocation(project_id, invocation_id) do
    invocation =
      ClickHouseRepo.one(
        from(invocation in Invocation,
          hints: ["FINAL"],
          where: invocation.project_id == ^project_id and invocation.invocation_id == ^invocation_id,
          order_by: [desc: invocation.inserted_at],
          limit: 1
        )
      )

    case invocation do
      nil -> {:error, :not_found}
      invocation -> {:ok, Map.put(invocation, :cache, ReapiCache.invocation_summary(project_id, invocation_id))}
    end
  end

  def summary(project_id) do
    result =
      ClickHouseRepo.one(
        from(invocation in Invocation,
          hints: ["FINAL"],
          where: invocation.project_id == ^project_id,
          select: %{
            total: count(invocation.id),
            successful: coalesce(sum(fragment("if(? = 'success', 1, 0)", invocation.status)), 0),
            median_duration_ms: fragment("quantileOrNull(0.5)(?)", invocation.duration_ms),
            p90_duration_ms: fragment("quantileOrNull(0.9)(?)", invocation.duration_ms)
          }
        )
      )

    result || %{total: 0, successful: 0, median_duration_ms: 0, p90_duration_ms: 0}
  end

  defp with_cache_summaries(_project_id, [], meta), do: {[], meta}

  defp with_cache_summaries(project_id, invocations, meta) do
    invocation_ids = Enum.map(invocations, & &1.invocation_id)
    summaries = ReapiCache.invocation_summaries(project_id, invocation_ids)

    invocations =
      Enum.map(invocations, fn invocation ->
        Map.put(invocation, :cache, Map.get(summaries, invocation.invocation_id, ReapiCache.empty_summary()))
      end)

    {invocations, meta}
  end
end
