defmodule Tuist.Builds.Timeline do
  @moduledoc """
  Full-build metadata for local timeline zooming, panning and search. Logs load separately.
  """
  import Ecto.Query

  alias Tuist.Builds.Step
  alias Tuist.ClickHouseRepo

  def load(build_id, opts \\ []) do
    events =
      ClickHouseRepo.all(
        from(e in Step,
          hints: ["FINAL"],
          where: e.build_run_id == ^build_id,
          order_by: [asc: e.start_ms, asc: e.event_id],
          select: map(e, [:event_id, :title, :target, :project, :category, :start_ms, :duration_ms, :status])
        )
      )

    duration =
      Enum.reduce(events, Keyword.get(opts, :duration, 1), fn event, duration ->
        max(duration, event.start_ms + event.duration_ms)
      end)

    target_count =
      events
      |> Enum.reject(&(&1.target == ""))
      |> MapSet.new(&{&1.project, &1.target})
      |> MapSet.size()

    %{events: events, total_count: length(events), duration: duration, target_count: target_count}
  end

  defp search_query(query, ""), do: query

  defp search_query(query, search) do
    from(e in query,
      where:
        fragment("positionCaseInsensitiveUTF8(concat(?, ' ', ?, ' ', ?), ?) > 0", e.title, e.target, e.project, ^search)
    )
  end

  defp current_step(query, event_id) when is_integer(event_id) do
    ClickHouseRepo.one(from(e in query, where: e.event_id == ^event_id, select: map(e, [:event_id, :start_ms]), limit: 1))
  end

  defp current_step(_query, _event_id), do: nil

  def neighbor(build_id, event_id, direction, opts) do
    query = from(e in Step, hints: ["FINAL"], where: e.build_run_id == ^build_id)

    current = current_step(query, event_id)

    search = opts |> Keyword.get(:search, "") |> String.slice(0, 512)

    query = search_query(query, search)

    query =
      case {direction, current} do
        {"next", %{start_ms: start, event_id: id}} ->
          from(e in query, where: e.start_ms > ^start or (e.start_ms == ^start and e.event_id > ^id))

        {"previous", %{start_ms: start, event_id: id}} ->
          from(e in query, where: e.start_ms < ^start or (e.start_ms == ^start and e.event_id < ^id))

        _ ->
          query
      end

    query =
      if direction == "next",
        do: from(e in query, order_by: [asc: e.start_ms, asc: e.event_id]),
        else: from(e in query, order_by: [desc: e.start_ms, desc: e.event_id])

    ClickHouseRepo.one(
      from(e in query,
        limit: 1,
        select: map(e, [:event_id, :title, :target, :project, :category, :start_ms, :duration_ms, :status])
      )
    )
  end
end
