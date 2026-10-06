defmodule Tuist.Mix.Timeline do
  @moduledoc """
  The work of a Mix build and its machine samples on one clock.

  Only work is shown. A file's steps are the stretches it was actually being
  compiled: the time it spent paused, waiting for a module another file was
  still defining, is left out as a gap rather than drawn. A wait the client
  could not place stays inside the file's step, since removing it would mean
  guessing where it happened. The remaining steps (type checking, writing
  modules to disk, other Mix compilers) are stored as reported.
  """
  import Ecto.Query

  alias Tuist.Builds.BuildMachineMetric
  alias Tuist.ClickHouseRepo
  alias Tuist.Mix.CompiledFile
  alias Tuist.Mix.Diagnostic
  alias Tuist.Mix.Step

  @metric_fields [
    :cpu_usage_percent,
    :memory_used_bytes,
    :memory_total_bytes,
    :network_bytes_in,
    :network_bytes_out,
    :disk_bytes_read,
    :disk_bytes_written
  ]

  def load(build, opts \\ []) do
    files = ClickHouseRepo.all(timed_files(build))

    failed_paths =
      MapSet.new(
        ClickHouseRepo.all(
          from(d in Diagnostic,
            where: d.build_id == ^build.id and d.project_id == ^build.project_id and d.severity == "error",
            select: d.file,
            distinct: true
          )
        )
      )

    steps = ClickHouseRepo.all(steps(build))

    if Keyword.get(opts, :include_metrics, true) do
      normalize(build, files, steps, failed_paths, samples(build))
    else
      timeline = normalize(build, files, steps, failed_paths, [])
      last_offset = last_sample_offset(build)
      has_metrics = is_number(last_offset) and last_offset >= 0
      duration = if has_metrics, do: max(timeline.duration, last_offset), else: timeline.duration
      timeline |> Map.merge(%{duration: duration, has_metrics: has_metrics}) |> Map.delete(:machine_metrics)
    end
  end

  def available?(build) do
    ClickHouseRepo.exists?(timed_files(build)) or ClickHouseRepo.exists?(steps(build)) or
      (not is_nil(origin(build)) and
         ClickHouseRepo.exists?(
           from(m in BuildMachineMetric,
             where:
               m.mix_build_id == ^build.id and m.project_id == ^build.project_id and m.timestamp * 1000 >= ^origin(build)
           )
         ))
  end

  def bootstrap(build) do
    build
    |> normalize([], [], MapSet.new(), samples(build))
    |> Map.drop([:events, :total_count, :target_count])
  end

  def normalize(build, files, steps, failed_paths, metrics) do
    origin = origin(build)

    events =
      files
      |> Enum.flat_map(&file_events(&1, MapSet.member?(failed_paths, &1.path)))
      |> Enum.concat(Enum.map(steps, &step_event/1))
      |> Enum.sort_by(&{&1.start_ms, &1.event_id})

    samples =
      if origin do
        metrics
        |> Enum.map(&(&1 |> Map.take(@metric_fields) |> Map.put(:offset_ms, &1.timestamp * 1000 - origin)))
        |> Enum.sort_by(& &1.offset_ms)
        |> then(fn samples ->
          # Keep the nearest real sample before the build so the first
          # interval is bracketed without inventing a reading at zero.
          {before, during} = Enum.split_while(samples, &(&1.offset_ms < 0))
          if during == [], do: [], else: Enum.take(before, -1) ++ during
        end)
      else
        []
      end

    duration = Enum.reduce(events, max(build.duration_ms, 1), &max(&2, &1.start_ms + &1.duration_ms))
    duration = Enum.reduce(samples, duration, &max(&2, &1.offset_ms))

    %{
      events: events,
      total_count: length(events),
      duration: duration,
      target_count: nil,
      machine_metrics: samples,
      has_metrics: samples != [],
      local_navigation: true,
      logs_available: false,
      time_origin: "build_start"
    }
  end

  defp timed_files(build) do
    from(f in CompiledFile,
      where: f.project_id == ^build.project_id and f.build_id == ^build.id and not is_nil(f.start_offset_ms)
    )
  end

  defp steps(build) do
    from(s in Step, where: s.project_id == ^build.project_id and s.build_id == ^build.id)
  end

  defp step_event(step) do
    %{
      event_id: "step:#{step.id}",
      title: step.title,
      project: "",
      target: step.path,
      category: step.category,
      start_ms: step.start_offset_ms,
      duration_ms: step.duration_ms,
      status: "success"
    }
  end

  defp samples(build),
    do:
      ClickHouseRepo.all(
        from(m in BuildMachineMetric, where: m.mix_build_id == ^build.id and m.project_id == ^build.project_id)
      )

  defp last_sample_offset(build) do
    with origin when not is_nil(origin) <- origin(build),
         last when is_number(last) <-
           ClickHouseRepo.one(
             from(m in BuildMachineMetric,
               where: m.mix_build_id == ^build.id and m.project_id == ^build.project_id,
               select: fragment("maxOrNull(?)", m.timestamp)
             )
           ) do
      last * 1000 - origin
    end
  end

  defp origin(%{started_at: nil}), do: nil
  defp origin(%{started_at: %DateTime{} = value}), do: DateTime.to_unix(value, :microsecond) / 1000

  defp origin(%{started_at: %NaiveDateTime{} = value}), do: origin(%{started_at: DateTime.from_naive!(value, "Etc/UTC")})

  defp file_events(file, failed?) do
    span_start = file.start_offset_ms
    span_end = span_start + file.compile_duration_ms + file.wait_duration_ms
    title = if file.modules == [], do: Path.basename(file.path), else: Enum.join(file.modules, ", ")

    {worked, cursor} =
      file
      |> placed_waits(span_start, span_end)
      |> Enum.reduce({[], span_start}, fn wait, {worked, cursor} ->
        wait_start = max(wait.start_ms, cursor)
        {stretch(worked, cursor, wait_start), max(wait.end_ms, wait_start)}
      end)

    worked
    |> stretch(cursor, span_end)
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.map(fn {{start_ms, end_ms}, index} ->
      %{
        event_id: "#{file.id}:#{index}",
        title: title,
        project: "",
        target: file.path,
        category: "compile",
        start_ms: start_ms,
        duration_ms: end_ms - start_ms,
        status: if(failed?, do: "failure", else: "success")
      }
    end)
  end

  defp stretch(worked, start_ms, end_ms) when end_ms <= start_ms, do: worked
  defp stretch(worked, start_ms, end_ms), do: [{start_ms, end_ms} | worked]

  defp placed_waits(file, span_start, span_end) do
    [file.wait_durations_ms, file.wait_start_offsets_ms]
    |> Enum.zip()
    |> Enum.flat_map(fn
      {duration_ms, start_ms} when is_integer(start_ms) and duration_ms > 0 ->
        start_ms = start_ms |> max(span_start) |> min(span_end)
        [%{start_ms: start_ms, end_ms: min(start_ms + duration_ms, span_end)}]

      _unplaced ->
        []
    end)
    |> Enum.sort_by(& &1.start_ms)
  end
end
