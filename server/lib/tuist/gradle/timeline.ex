defmodule Tuist.Gradle.Timeline do
  @moduledoc """
  Recorded Gradle operations and machine samples on one clock, without retaining another copy.
  """
  import Ecto.Query

  alias Tuist.Builds.BuildMachineMetric
  alias Tuist.ClickHouseRepo
  alias Tuist.Gradle.ArtifactTransform
  alias Tuist.Gradle.ConfigurationOperation
  alias Tuist.Gradle.Task

  @metric_fields [
    :cpu_usage_percent,
    :memory_used_bytes,
    :memory_total_bytes,
    :network_bytes_in,
    :network_bytes_out,
    :disk_bytes_read,
    :disk_bytes_written
  ]

  def load(build) do
    tasks = rows(Task, build, [:id, :task_path, :build_path, :task_type, :outcome, :started_at, :duration_ms])

    configuration =
      rows(ConfigurationOperation, build, [:id, :phase, :build_path, :project_path, :started_at, :duration_ms])

    transforms =
      rows(ArtifactTransform, build, [
        :id,
        :transformer_name,
        :subject_name,
        :consumer_project_path,
        :started_at,
        :duration_ms
      ])

    metrics = ClickHouseRepo.all(from(m in BuildMachineMetric, where: m.gradle_build_id == ^build.id))
    normalize(build, tasks, configuration, transforms, metrics)
  end

  def step_query(build) do
    origin = timestamp(build.started_at) || recorded_origin(build)

    tasks =
      from(row in Task,
        where: row.gradle_build_id == ^build.id and row.project_id == ^build.project_id,
        select: %{
          event_id: fragment("concat('task:', toString(?))", row.id),
          title: row.task_path,
          project: row.build_path,
          target: row.task_path,
          category: fragment("if(empty(?), 'task', ?)", row.task_type, row.task_type),
          start_ms: fragment("toUnixTimestamp64Micro(?) / 1000 - ?", row.started_at, ^origin),
          duration_ms: row.duration_ms,
          status:
            fragment(
              "multiIf(? = 'executed', 'success', ? = 'failed', 'failure', ?)",
              row.outcome,
              row.outcome,
              row.outcome
            )
        }
      )

    configuration =
      from(row in ConfigurationOperation,
        where: row.gradle_build_id == ^build.id and row.project_id == ^build.project_id,
        select: %{
          event_id: fragment("concat('configuration:', toString(?))", row.id),
          title: row.phase,
          project: row.build_path,
          target: row.project_path,
          category: "configuration",
          start_ms: fragment("toUnixTimestamp64Micro(?) / 1000 - ?", row.started_at, ^origin),
          duration_ms: row.duration_ms,
          status: "unknown"
        }
      )

    transforms =
      from(row in ArtifactTransform,
        where: row.gradle_build_id == ^build.id and row.project_id == ^build.project_id,
        select: %{
          event_id: fragment("concat('transform:', toString(?))", row.id),
          title: fragment("concat(?, ' · ', ?)", row.transformer_name, row.subject_name),
          project: ^(build.root_project_name || ""),
          target: row.consumer_project_path,
          category: "transform",
          start_ms: fragment("toUnixTimestamp64Micro(?) / 1000 - ?", row.started_at, ^origin),
          duration_ms: row.duration_ms,
          status: "unknown"
        }
      )

    rows = tasks |> union_all(^configuration) |> union_all(^transforms)
    from(row in subquery(rows), where: row.start_ms >= 0 and row.duration_ms > 0)
  end

  defp recorded_origin(build) do
    operations =
      Enum.map([Task, ConfigurationOperation, ArtifactTransform], fn schema ->
        ClickHouseRepo.one(
          from(row in schema,
            where: row.gradle_build_id == ^build.id and row.project_id == ^build.project_id,
            select: fragment("minOrNull(toUnixTimestamp64Micro(?)) / 1000", row.started_at)
          )
        )
      end)

    metric =
      ClickHouseRepo.one(
        from(row in BuildMachineMetric,
          where: row.gradle_build_id == ^build.id,
          select: fragment("minOrNull(?) * 1000", row.timestamp)
        )
      )

    [metric | operations] |> Enum.reject(&is_nil/1) |> Enum.min(fn -> 0 end)
  end

  defp rows(schema, build, fields) do
    ClickHouseRepo.all(
      from(row in schema,
        where: row.gradle_build_id == ^build.id and row.project_id == ^build.project_id,
        select: map(row, ^fields)
      )
    )
  end

  def normalize(build, tasks, configuration, transforms, metrics) do
    operations =
      Enum.map(tasks, &operation(&1, "task", &1.task_path, &1.build_path, &1.task_path, &1.task_type, &1.outcome)) ++
        Enum.map(
          configuration,
          &operation(&1, "configuration", &1.phase, &1.build_path, &1.project_path, "configuration", "unknown")
        ) ++
        Enum.map(
          transforms,
          &operation(
            &1,
            "transform",
            &1.transformer_name <> " · " <> &1.subject_name,
            build.root_project_name,
            &1.consumer_project_path,
            "transform",
            "unknown"
          )
        )

    recorded_times =
      Enum.flat_map(operations, fn op -> if op.timestamp, do: [op.timestamp], else: [] end) ++
        Enum.map(metrics, &(&1.timestamp * 1000))

    origin = timestamp(build.started_at) || Enum.min(recorded_times, fn -> 0 end)

    events =
      operations
      |> Enum.filter(&(is_number(&1.timestamp) and &1.timestamp >= origin and &1.duration_ms > 0))
      |> Enum.map(&(&1 |> Map.put(:start_ms, &1.timestamp - origin) |> Map.delete(:timestamp)))
      |> Enum.sort_by(&{&1.start_ms, &1.event_id})

    samples =
      metrics
      |> Enum.map(&(&1 |> Map.take(@metric_fields) |> Map.put(:offset_ms, &1.timestamp * 1000 - origin)))
      |> Enum.sort_by(& &1.offset_ms)
      |> then(fn samples ->
        {before, during} = Enum.split_while(samples, &(&1.offset_ms < 0))
        if during == [], do: [], else: Enum.take(before, -1) ++ during
      end)

    duration = Enum.reduce(events, max(build.duration_ms, 1), &max(&2, &1.start_ms + &1.duration_ms))
    duration = Enum.reduce(samples, duration, &max(&2, &1.offset_ms))

    %{
      events: events,
      total_count: length(events),
      duration: duration,
      target_count: events |> Enum.reject(&(&1.target == "")) |> Enum.uniq_by(&{&1.project, &1.target}) |> length(),
      machine_metrics: samples,
      has_metrics: samples != [],
      local_navigation: true,
      logs_available: false,
      time_origin: if(build.started_at, do: "build_start", else: "first_recorded_timestamp")
    }
  end

  defp operation(row, kind, title, project, target, category, outcome) do
    %{
      event_id: kind <> ":" <> row.id,
      title: title || "",
      project: project || "",
      target: target || "",
      category: if(category in [nil, ""], do: kind, else: category),
      timestamp: timestamp(row.started_at),
      duration_ms: row.duration_ms,
      status:
        case outcome do
          "executed" -> "success"
          "failed" -> "failure"
          value -> value
        end
    }
  end

  defp timestamp(nil), do: nil
  defp timestamp(%DateTime{} = value), do: DateTime.to_unix(value, :microsecond) / 1000
  defp timestamp(%NaiveDateTime{} = value), do: value |> DateTime.from_naive!("Etc/UTC") |> timestamp()
end
