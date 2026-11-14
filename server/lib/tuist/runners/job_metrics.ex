defmodule Tuist.Runners.JobMetrics do
  @moduledoc """
  ClickHouse-backed store for runner-job machine metrics. Writes are
  batch INSERTs from the runner metrics collector (POSTed via
  `TuistWeb.RunnerJobMetricsController`); reads serve the job detail
  page's Overview charts and Metrics tab.

  Re-delivered collector batches collapse on the ReplacingMergeTree
  `(workflow_job_id, timestamp)` key with `inserted_at` as the
  version, so an at-least-once retry is a no-op merge.
  """
  use Gettext, backend: TuistWeb.Gettext

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Runners.JobMachineMetric
  alias Tuist.Utilities.ByteFormatter

  @float_fields [:cpu_usage_percent, :cpu_iowait_percent]
  @integer_fields [
    :memory_used_bytes,
    :memory_total_bytes,
    :network_bytes_in,
    :network_bytes_out,
    :disk_used_bytes,
    :disk_total_bytes,
    :oom_kill_count,
    :oom_victim_memory_bytes
  ]
  @string_fields [:oom_victim_process, :oom_victim_container, :oom_victim_image]
  @sample_fields @float_fields ++ @integer_fields ++ @string_fields

  @doc """
  Inserts a batch of metric samples for a job. Each sample carries
  `:timestamp` (epoch seconds) plus any subset of `#{inspect(@sample_fields)}`;
  missing fields default to `0`, or `""` for the OOM victim's names. `:inserted_at` is stamped here as
  the RMT version so a retried batch resolves to the latest write.

  An empty sample list is a no-op.
  """
  def record(_workflow_job_id, _account_id, []), do: :ok

  def record(workflow_job_id, account_id, samples)
      when is_integer(workflow_job_id) and is_integer(account_id) and is_list(samples) do
    now = DateTime.utc_now()

    rows =
      Enum.map(samples, fn sample ->
        @sample_fields
        |> Map.new(fn field -> {field, coerce(field, Map.get(sample, field, default(field)))} end)
        |> Map.merge(%{
          workflow_job_id: workflow_job_id,
          account_id: account_id,
          timestamp: Map.fetch!(sample, :timestamp) / 1,
          inserted_at: now
        })
      end)

    IngestRepo.insert_all(JobMachineMetric, rows)
    :ok
  end

  # The `Float32`/`Int64` ClickHouse columns reject the wrong numeric
  # kind on dump (an integer `0` default won't go into `Float32`), so
  # coerce each value to its column's type before insert.
  defp default(field) when field in @string_fields, do: ""
  defp default(_field), do: 0

  defp coerce(field, value) when field in @float_fields, do: value / 1
  defp coerce(field, value) when field in @integer_fields, do: trunc(value)
  defp coerce(field, value) when field in @string_fields, do: value

  @doc """
  Lists a job's metric samples in time order. Returns maps with
  `:timestamp` and every field in `#{inspect(@sample_fields)}`.

  Uses `argMax(col, inserted_at) GROUP BY (workflow_job_id, timestamp)`
  so a re-delivered batch collapses to one row per timestamp without
  paying for `FINAL`'s part merge — the same pattern `JobSteps` uses.
  """
  def list_for_job(workflow_job_id) when is_integer(workflow_job_id) do
    ClickHouseRepo.all(
      from(m in JobMachineMetric,
        where: m.workflow_job_id == ^workflow_job_id,
        group_by: [m.workflow_job_id, m.timestamp],
        order_by: [asc: m.timestamp],
        select: %{
          timestamp: m.timestamp,
          cpu_usage_percent: fragment("argMax(?, ?)", m.cpu_usage_percent, m.inserted_at),
          cpu_iowait_percent: fragment("argMax(?, ?)", m.cpu_iowait_percent, m.inserted_at),
          memory_used_bytes: fragment("argMax(?, ?)", m.memory_used_bytes, m.inserted_at),
          memory_total_bytes: fragment("argMax(?, ?)", m.memory_total_bytes, m.inserted_at),
          network_bytes_in: fragment("argMax(?, ?)", m.network_bytes_in, m.inserted_at),
          network_bytes_out: fragment("argMax(?, ?)", m.network_bytes_out, m.inserted_at),
          disk_used_bytes: fragment("argMax(?, ?)", m.disk_used_bytes, m.inserted_at),
          disk_total_bytes: fragment("argMax(?, ?)", m.disk_total_bytes, m.inserted_at),
          oom_kill_count: fragment("argMax(?, ?)", m.oom_kill_count, m.inserted_at),
          oom_victim_process: fragment("argMax(?, ?)", m.oom_victim_process, m.inserted_at),
          oom_victim_memory_bytes: fragment("argMax(?, ?)", m.oom_victim_memory_bytes, m.inserted_at),
          oom_victim_container: fragment("argMax(?, ?)", m.oom_victim_container, m.inserted_at),
          oom_victim_image: fragment("argMax(?, ?)", m.oom_victim_image, m.inserted_at)
        }
      )
    )
  end

  @doc """
  Summarizes what the runner VM killed for running out of memory during
  the job, from the samples `list_for_job/1` returned, or `nil` when it
  killed nothing.

    * `:count` — processes killed: the highest running count among the
      samples, since a redelivered batch can make an earlier sample the
      last write.
    * `:at` — epoch seconds of the first sample that reported a kill.
    * `:victim` — the process killed last, from the sample with the
      highest count that names one: a map of `:process`,
      `:memory_bytes`, `:container` and `:image` (`nil` when unknown),
      or `nil` when no sample names it (pools without the dind sidecar).
  """
  def out_of_memory(metrics) when is_list(metrics) do
    case Enum.filter(metrics, &(&1.oom_kill_count > 0)) do
      [] ->
        nil

      [first | _] = killed ->
        victim =
          killed
          |> Enum.filter(&(&1.oom_victim_process != ""))
          |> Enum.max_by(&{&1.oom_kill_count, &1.timestamp}, fn -> nil end)

        %{
          count: killed |> Enum.map(& &1.oom_kill_count) |> Enum.max(),
          at: first.timestamp,
          victim: victim && victim_details(victim)
        }
    end
  end

  @runner_processes ~w(Runner.Listener Runner.Worker)

  @doc """
  Describes an `out_of_memory/1` summary for people: how many processes
  the system stopped, which one it stopped last and where, and advice
  that fits it — the JVM heap only when that process was a JVM. The job
  page's "Ran out of memory" alert and `out_of_memory_payload/1` show it.
  """
  def out_of_memory_description(%{count: count, victim: victim}) do
    lead =
      dngettext(
        "dashboard_runners",
        "The runner's machine ran out of memory, and the system stopped a process to free it.",
        "The runner's machine ran out of memory, and the system stopped %{count} processes to free it.",
        count
      )

    Enum.join([lead | out_of_memory_details(victim, count)], " ")
  end

  defp out_of_memory_details(nil, _count) do
    [
      dgettext(
        "dashboard_runners",
        "A stopped process fails the step that started it; if it was the runner itself, GitHub reports that the runner lost communication."
      ),
      out_of_memory_advice(nil)
    ]
  end

  defp out_of_memory_details(%{process: process, container: nil} = victim, count) when process in @runner_processes do
    [
      dngettext(
        "dashboard_runners",
        "It stopped the GitHub runner itself (%{process}), so GitHub reports that the runner lost communication.",
        "The last one was the GitHub runner itself (%{process}), so GitHub reports that the runner lost communication.",
        count,
        process: process
      ),
      out_of_memory_advice(victim)
    ]
  end

  defp out_of_memory_details(victim, count) do
    bindings = [
      process: victim.process,
      memory: ByteFormatter.format_bytes(victim.memory_bytes),
      container: victim.container,
      image: victim.image
    ]

    stopped =
      case victim do
        %{container: nil} ->
          dngettext(
            "dashboard_runners",
            "It stopped %{process}, which was using %{memory}, outside any container.",
            "The last one was %{process}, which was using %{memory}, outside any container.",
            count,
            bindings
          )

        %{container: "docker-build"} ->
          dngettext(
            "dashboard_runners",
            "It stopped %{process}, which was using %{memory}, in a Docker build step.",
            "The last one was %{process}, which was using %{memory}, in a Docker build step.",
            count,
            bindings
          )

        %{image: nil} ->
          dngettext(
            "dashboard_runners",
            "It stopped %{process}, which was using %{memory}, in the container %{container}.",
            "The last one was %{process}, which was using %{memory}, in the container %{container}.",
            count,
            bindings
          )

        _ ->
          dngettext(
            "dashboard_runners",
            "It stopped %{process}, which was using %{memory}, in the container %{container} (%{image}).",
            "The last one was %{process}, which was using %{memory}, in the container %{container} (%{image}).",
            count,
            bindings
          )
      end

    [
      stopped,
      dgettext("dashboard_runners", "A stopped process fails the step that started it."),
      out_of_memory_advice(victim)
    ]
  end

  defp out_of_memory_advice(%{process: "java"}) do
    dgettext(
      "dashboard_runners",
      "Lower the JVM heap your build uses, for example org.gradle.jvmargs or kotlin.daemon.jvmargs, or use a runner with more memory."
    )
  end

  defp out_of_memory_advice(_victim) do
    dgettext("dashboard_runners", "Lower the memory your build uses, or use a runner with more memory.")
  end

  @doc """
  The `out_of_memory` field that `getRunnerJob` and the `get_runner_job`
  MCP tool return: the job's `out_of_memory/1` summary with the time of
  the first kill as ISO 8601 and its `out_of_memory_description/1`, or
  `nil` when the runner VM killed nothing.
  """
  def out_of_memory_report(workflow_job_id) when is_integer(workflow_job_id) do
    case workflow_job_id |> list_for_job() |> out_of_memory() do
      nil ->
        nil

      %{count: count, at: at, victim: victim} = out_of_memory ->
        %{
          kill_count: count,
          first_kill_at: (at * 1000) |> round() |> DateTime.from_unix!(:millisecond) |> DateTime.to_iso8601(),
          victim: victim,
          description: out_of_memory_description(out_of_memory)
        }
    end
  end

  defp victim_details(sample) do
    %{
      process: sample.oom_victim_process,
      memory_bytes: sample.oom_victim_memory_bytes,
      container: blank_to_nil(sample.oom_victim_container),
      image: blank_to_nil(sample.oom_victim_image)
    }
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
