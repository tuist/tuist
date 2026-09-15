defmodule Tuist.Once do
  @moduledoc """
  Ingestion and read APIs for [Once](https://once.tuist.dev).

  Once wraps arbitrary project automation in cacheable actions backed by a
  Bazel-compatible content-addressed store. Tuist accepts a summary from the
  Once CLI after each `once exec` completes and surfaces the results per
  project. This module is the read/write boundary; the controller keeps the
  parsing and validation.
  """

  import Ecto.Query

  alias Tuist.Once.Invocation
  alias Tuist.Repo

  def create_invocations([]), do: {0, nil}

  def create_invocations(invocations) when is_list(invocations) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    entries =
      Enum.map(invocations, fn invocation ->
        invocation
        |> Map.put_new(:command, "exec")
        |> Map.put_new(:cache, "miss")
        |> Map.put_new(:argv, [])
        |> Map.put(:id, UUIDv7.generate())
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    Repo.insert_all(
      Invocation,
      entries,
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:project_id, :invocation_id]
    )
  end

  def list_invocations(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Invocation
    |> where([i], i.project_id == ^project_id)
    |> order_by([i], desc: i.finished_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_invocation(project_id, invocation_id) do
    Invocation
    |> where([i], i.project_id == ^project_id and i.invocation_id == ^invocation_id)
    |> Repo.one()
  end

  def cache_hit_ratio(project_id, opts \\ []) do
    since = Keyword.get(opts, :since, DateTime.add(DateTime.utc_now(), -30, :day))

    query =
      from i in Invocation,
        where: i.project_id == ^project_id and i.inserted_at >= ^since,
        select: %{
          total: count(i.id),
          hits: sum(fragment("case when ? = 'hit' then 1 else 0 end", i.cache))
        }

    case Repo.one(query) do
      %{total: 0} -> 0.0
      %{total: total, hits: hits} when is_integer(total) and is_integer(hits) -> hits / total
      _ -> 0.0
    end
  end
end
