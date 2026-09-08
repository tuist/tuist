defmodule Tuist.Builds.Timeline do
  @moduledoc """
  Bounded timeline views of all recorded build steps. Dense ranges use occupied
  time buckets; their counts describe overlapping operations, not CPU usage.
  """
  import Ecto.Query

  alias Tuist.Builds.Step
  alias Tuist.ClickHouseRepo

  @detail_limit 1_500
  @bins 128

  def load(build_id, opts \\ []) do
    search = opts |> Keyword.get(:search, "") |> String.slice(0, 512)
    target = Keyword.get(opts, :target, "")
    project = Keyword.get(opts, :project, "")
    base = from(e in Step, hints: ["FINAL"], where: e.build_run_id == ^build_id)

    {_, duration} =
      ClickHouseRepo.one(from(e in base, select: {count(), max(fragment("? + ?", e.start_ms, e.duration_ms))}))

    base = if target == "", do: base, else: from(e in base, where: e.target == ^target and e.project == ^project)

    base =
      from(e in base,
        where:
          fragment("positionCaseInsensitiveUTF8(concat(?, ' ', ?, ' ', ?), ?) > 0", e.title, e.target, e.project, ^search)
      )

    total = ClickHouseRepo.one(from(e in base, select: count()))
    duration = max(duration || 0, 1)
    start = min(max(Keyword.get(opts, :start, 0), 0), duration)
    span = min(max(Keyword.get(opts, :span, duration), 1), max(duration - start, 1))
    finish = start + span
    scoped = from(e in base, where: e.start_ms < ^finish and fragment("? + ?", e.start_ms, e.duration_ms) > ^start)

    events =
      ClickHouseRepo.all(
        from(e in scoped,
          order_by: [asc: e.start_ms, asc: e.event_id],
          limit: ^(@detail_limit + 1),
          select: map(e, [:event_id, :title, :target, :project, :category, :start_ms, :duration_ms, :status])
        )
      )

    grouped = length(events) > @detail_limit
    events = if grouped, do: buckets(build_id, start, span, search, target, project), else: events

    %{
      events: events,
      grouped: grouped,
      truncated: false,
      total_count: total,
      duration: duration,
      range: %{start: start, span: span}
    }
  end

  def targets(build_id) do
    ClickHouseRepo.all(
      from(e in Step,
        hints: ["FINAL"],
        where: e.build_run_id == ^build_id and e.target != "",
        distinct: true,
        order_by: [asc: e.project, asc: e.target],
        select: map(e, [:project, :target])
      )
    )
  end

  def neighbor(build_id, event_id, direction, opts) do
    query = from(e in Step, hints: ["FINAL"], where: e.build_run_id == ^build_id)

    current =
      if is_integer(event_id),
        do:
          ClickHouseRepo.one(
            from(e in query, where: e.event_id == ^event_id, select: map(e, [:event_id, :start_ms]), limit: 1)
          )

    search = opts |> Keyword.get(:search, "") |> String.slice(0, 512)

    query =
      from(e in query,
        where:
          fragment("positionCaseInsensitiveUTF8(concat(?, ' ', ?, ' ', ?), ?) > 0", e.title, e.target, e.project, ^search)
      )

    target = Keyword.get(opts, :target, "")
    project = Keyword.get(opts, :project, "")
    query = if target == "", do: query, else: from(e in query, where: e.target == ^target and e.project == ^project)

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

  defp buckets(build_id, start, span, search, target, project) do
    sql = """
    SELECT bucket, kind, count() AS steps
    FROM (
      SELECT arrayJoin(range(
        toUInt32(greatest(0, floor((greatest(start_ms, {start:Float64}) - {start:Float64}) / {width:Float64}))),
        toUInt32(least(#{@bins}, ceil((least(start_ms + duration_ms, {finish:Float64}) - {start:Float64}) / {width:Float64})))
      )) AS bucket,
      multiIf(status = 'failure', 'failure',
        match(category, '(?i)compilation|swiftmodule|bridgingheader'), 'compile',
        match(category, '(?i)linker|staticlibrary'), 'link',
        match(category, '(?i)script'), 'script',
        match(category, '(?i)cop|resource|asset|storyboard|xib'), 'resource', 'other') AS kind
      FROM build_steps FINAL
      WHERE build_run_id = {build_id:UUID}
        AND start_ms < {finish:Float64} AND start_ms + duration_ms > {start:Float64}
        AND positionCaseInsensitiveUTF8(concat(title, ' ', target, ' ', project), {search:String}) > 0
        AND ({target:String} = '' OR (target = {target:String} AND project = {project:String}))
    )
    GROUP BY bucket, kind
    ORDER BY kind, bucket
    """

    width = span / @bins

    {:ok, %{rows: rows}} =
      ClickHouseRepo.query(sql, %{
        build_id: build_id,
        start: start,
        finish: start + span,
        width: width,
        search: search,
        target: target,
        project: project
      })

    Enum.map(rows, fn [bucket, kind, count] ->
      %{
        event_id: "#{kind}:#{bucket}",
        aggregate: true,
        count: count,
        title: "",
        target: "",
        project: "",
        category: kind,
        status: if(kind == "failure", do: "failure", else: "success"),
        start_ms: start + bucket * width,
        duration_ms: width
      }
    end)
  end
end
