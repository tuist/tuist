defmodule Tuist.Builds.RecordedSteps do
  @moduledoc """
  Shared filtering for Gradle operations and Bazel's bounded retained spans.
  Callers must authorize the parent build before loading its steps.
  """
  import Ecto.Query

  alias Tuist.Bazel
  alias Tuist.Builds.StepOptions
  alias Tuist.Builds.Steps
  alias Tuist.ClickHouseRepo
  alias Tuist.Gradle
  alias Tuist.MCP.Components.Tools.RunnerTools

  @statuses ~w(success failure unknown local_hit remote_hit cache_hit up_to_date skipped no_source)

  def list(%Bazel.Invocation{} = build, params) do
    case Bazel.Profile.steps_version(build) do
      version when is_binary(version) and version != "" -> Bazel.ProfileSteps.list(build, version, params)
      _ -> list_recorded(build, params)
    end
  end

  def list(%Gradle.Build{} = build, params) do
    with {:ok, opts} <- StepOptions.options(params, @statuses) do
      base = Gradle.Timeline.step_query(build)
      filtered = Steps.filter(base, opts)
      count = ClickHouseRepo.aggregate(filtered, :count)

      steps =
        filtered
        |> Steps.order(opts.sort_by)
        |> limit(^opts.page_size)
        |> offset(^((opts.page - 1) * opts.page_size))
        |> ClickHouseRepo.all()
        |> Enum.map(&serialize/1)

      {:ok,
       %{
         steps: steps,
         availability: if(count > 0 or ClickHouseRepo.exists?(base), do: "available", else: "unavailable"),
         time_origin: if(build.started_at, do: "build_start", else: "first_recorded_timestamp"),
         coverage: "recorded_operations",
         pagination_metadata: RunnerTools.pagination_metadata(opts.page, opts.page_size, count)
       }}
    end
  end

  def list(build, params), do: list_recorded(build, params)

  defp list_recorded(build, params) do
    with {:ok, opts} <- StepOptions.options(params, @statuses) do
      timeline = load(build)
      steps = timeline.events |> Enum.filter(&matches?(&1, opts)) |> Enum.sort_by(&sort_key(&1, opts.sort_by))
      count = length(steps)

      {:ok,
       %{
         steps: steps |> Enum.slice((opts.page - 1) * opts.page_size, opts.page_size) |> Enum.map(&serialize/1),
         availability: availability(build, timeline),
         time_origin: timeline.time_origin,
         coverage: Map.get(timeline, :coverage, "recorded_operations"),
         pagination_metadata: RunnerTools.pagination_metadata(opts.page, opts.page_size, count)
       }}
    end
  end

  def get(%Bazel.Invocation{} = build, id) when is_binary(id) and byte_size(id) <= 128 do
    case Bazel.Profile.steps_version(build) do
      version when is_binary(version) and version != "" ->
        case Bazel.ProfileSteps.get(build, version, id) do
          {:error, :not_found} -> get_retained(build, id)
          result -> result
        end

      _ ->
        get_recorded(build, id)
    end
  end

  def get(%Gradle.Build{} = build, id) when is_binary(id) and byte_size(id) <= 128 do
    case ClickHouseRepo.one(from(s in Gradle.Timeline.step_query(build), where: s.event_id == ^id, limit: 1)) do
      nil -> {:error, :not_found}
      step -> {:ok, Map.merge(serialize(step), %{log: nil, log_truncated: false})}
    end
  end

  def get(build, id) when is_binary(id) and byte_size(id) <= 128 do
    get_recorded(build, id)
  end

  def get(_build, _id), do: {:error, :invalid_step_id}

  defp get_retained(build, id) do
    if Regex.match?(~r/^\d+$/, id) do
      find_step(build, Bazel.Timeline.retained_summary(build), id)
    else
      {:error, :not_found}
    end
  end

  defp get_recorded(build, id) do
    find_step(build, load(build), id)
  end

  defp find_step(build, timeline, id) do
    case Enum.find(timeline.events, &(&1.event_id == id)) do
      nil -> {:error, :not_found}
      step -> {:ok, Map.merge(serialize(step), step_log(build, step))}
    end
  end

  defp availability(%Bazel.Invocation{} = build, timeline) do
    if timeline.coverage != "trace_profile" and Bazel.ProfileUpload.state(build) == "pending",
      do: "processing",
      else: if(timeline.total_count > 0, do: "available", else: "unavailable")
  end

  defp availability(_build, timeline), do: if(timeline.total_count > 0, do: "available", else: "unavailable")

  defp load(%Gradle.Build{} = build), do: Gradle.Timeline.load(build)
  defp load(%Bazel.Invocation{} = invocation), do: Bazel.Timeline.load(invocation)

  defp matches?(step, opts) do
    Enum.all?([:project, :target, :category, :status], &(is_nil(opts[&1]) or step[&1] == opts[&1])) and
      (is_nil(opts[:start_ms]) or step.start_ms + step.duration_ms > opts.start_ms) and
      (is_nil(opts[:end_ms]) or step.start_ms < opts.end_ms) and
      (is_nil(opts[:search]) or
         String.contains?(
           String.downcase(Enum.join([step.title, step.project, step.target], " ")),
           String.downcase(opts.search)
         ))
  end

  defp sort_key(step, "start_ms"), do: {step.start_ms, step.event_id}
  defp sort_key(step, "duration_ms"), do: {-step.duration_ms, step.event_id}
  defp step_log(%Bazel.Invocation{} = build, step), do: Bazel.Action.log(build, step)
  defp step_log(_, _), do: %{log: nil, log_truncated: false}

  defp serialize(step),
    do: step |> Map.put(:id, step.event_id) |> Map.drop([:event_id, :primary_output, :action_started_at_ms])
end
