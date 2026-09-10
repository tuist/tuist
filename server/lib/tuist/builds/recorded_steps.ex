defmodule Tuist.Builds.RecordedSteps do
  @moduledoc """
  Shared filtering for Gradle operations and Bazel's bounded retained spans.
  Callers must authorize the parent build before loading its steps.
  """
  alias Ecto.Changeset
  alias Tuist.Bazel
  alias Tuist.Gradle

  @types %{
    page: :integer,
    page_size: :integer,
    search: :string,
    project: :string,
    target: :string,
    category: :string,
    status: :string,
    start_ms: :float,
    end_ms: :float,
    sort_by: :string
  }
  @statuses ~w(success failure unknown local_hit remote_hit cache_hit up_to_date skipped no_source)

  def list(build, params) do
    with {:ok, opts} <- options(params) do
      timeline = load(build)
      steps = timeline.events |> Enum.filter(&matches?(&1, opts)) |> Enum.sort_by(&sort_key(&1, opts.sort_by))
      count = length(steps)
      pages = ceil(count / opts.page_size)

      {:ok,
       %{
         steps: steps |> Enum.slice((opts.page - 1) * opts.page_size, opts.page_size) |> Enum.map(&serialize/1),
         availability: if(timeline.total_count > 0, do: "available", else: "unavailable"),
         time_origin: timeline.time_origin,
         coverage: Map.get(timeline, :coverage, "recorded_operations"),
         pagination_metadata: %{
           current_page: opts.page,
           page_size: opts.page_size,
           total_count: count,
           total_pages: pages,
           has_next_page: opts.page < pages,
           has_previous_page: opts.page > 1
         }
       }}
    end
  end

  def get(build, id) when is_binary(id) and byte_size(id) <= 128 do
    case Enum.find(load(build).events, &(&1.event_id == id)) do
      nil -> {:error, :not_found}
      step -> {:ok, Map.merge(serialize(step), step_log(build, step))}
    end
  end

  def get(_build, _id), do: {:error, :invalid_step_id}

  defp load(%Gradle.Build{} = build), do: Gradle.Timeline.load(build)
  defp load(%Bazel.Invocation{} = invocation), do: Bazel.Timeline.load(invocation)

  defp options(params) do
    changeset =
      {%{page: 1, page_size: 20, sort_by: "duration_ms"}, @types}
      |> Changeset.cast(params, Map.keys(@types))
      |> Changeset.validate_required([:page, :page_size, :sort_by])
      |> Changeset.validate_number(:page, greater_than: 0, less_than_or_equal_to: 100_000)
      |> Changeset.validate_number(:page_size, greater_than: 0, less_than_or_equal_to: 100)
      |> Changeset.validate_number(:start_ms, greater_than_or_equal_to: 0)
      |> Changeset.validate_number(:end_ms, greater_than_or_equal_to: 0)
      |> Changeset.validate_length(:search, max: 512)
      |> Changeset.validate_length(:project, max: 512)
      |> Changeset.validate_length(:target, max: 512)
      |> Changeset.validate_length(:category, max: 128)
      |> Changeset.validate_inclusion(:status, @statuses)
      |> Changeset.validate_inclusion(:sort_by, ["duration_ms", "start_ms"])

    case Changeset.apply_action(changeset, :validate) do
      {:ok, opts} ->
        if opts[:start_ms] && opts[:end_ms] && opts.end_ms <= opts.start_ms,
          do: {:error, :invalid_range},
          else: {:ok, opts}

      {:error, _} ->
        {:error, :invalid_filters}
    end
  end

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
