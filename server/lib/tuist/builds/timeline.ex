defmodule Tuist.Builds.Timeline do
  @moduledoc """
  Time-windowed views of recorded build steps, with a surrounding buffer for local zooming.
  """
  import Ecto.Query

  alias Tuist.Builds.Step
  alias Tuist.ClickHouseRepo

  @buffer 60_000

  def load(build_id, opts \\ []) do
    search = opts |> Keyword.get(:search, "") |> String.slice(0, 512)
    base = from(e in Step, hints: ["FINAL"], where: e.build_run_id == ^build_id)

    summary = Keyword.get(opts, :summary)

    {total, duration} =
      case summary do
        %{total_count: total, duration: duration} -> {total, duration}
        _ -> ClickHouseRepo.one(from(e in base, select: {count(), max(fragment("? + ?", e.start_ms, e.duration_ms))}))
      end

    base = search_query(base, search)

    total = if search == "", do: total, else: ClickHouseRepo.one(from(e in base, select: count()))
    duration = max(duration || 0, Keyword.get(opts, :duration, 1))
    span = min(max(Keyword.get(opts, :span, duration), 1), duration)
    start = min(max(Keyword.get(opts, :start, 0), 0), max(duration - span, 0))
    loaded_start = max(0, start - @buffer)
    finish = min(duration, start + span + @buffer)
    scoped = from(e in base, where: e.start_ms < ^finish and fragment("? + ?", e.start_ms, e.duration_ms) > ^loaded_start)

    events =
      ClickHouseRepo.all(
        from(e in scoped,
          order_by: [asc: e.start_ms, asc: e.event_id],
          select: map(e, [:event_id, :title, :target, :project, :category, :start_ms, :duration_ms, :status])
        )
      )

    %{
      events: events,
      total_count: total,
      duration: duration,
      range: %{start: start, span: span},
      loaded_range: %{start: loaded_start, span: finish - loaded_start},
      max_span: duration
    }
  end

  def target_count(build_id) do
    ClickHouseRepo.one(
      from(e in Step,
        hints: ["FINAL"],
        where: e.build_run_id == ^build_id and e.target != "",
        select: fragment("uniqExact((?, ?))", e.project, e.target)
      )
    )
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
