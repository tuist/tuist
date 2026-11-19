defmodule Tuist.Builds.Trace do
  @moduledoc """
  Exports a build's recorded timeline as a Chrome Trace Event JSON
  document, which Perfetto (https://ui.perfetto.dev), `chrome://tracing`,
  and Perfetto's trace processor open directly.

  `encode/2` reads the timeline shape every build system already produces
  for the dashboard: `events` with `start_ms`/`duration_ms` offsets from
  the build start, and `machine_metrics` samples with an `offset_ms`. Any
  other source that produces that shape, such as a CI pipeline, can be
  exported the same way.
  """

  alias Tuist.Bazel
  alias Tuist.Builds
  alias Tuist.ClickHouseRepo
  alias Tuist.Gradle
  alias Tuist.Mix

  @token_salt "build trace"
  @token_max_age 3_600
  @gib 1024 * 1024 * 1024

  @doc """
  Loads the build with `id` that belongs to `project`, according to the
  project's build system.
  """
  def get_build(%{build_system: :xcode} = project, id), do: Builds.get_build(id, project_id: project.id)
  def get_build(%{build_system: :gradle} = project, id), do: Gradle.get_build(id, project_id: project.id)
  def get_build(%{build_system: :mix} = project, id), do: Mix.get_build(id, project.id)

  def get_build(%{build_system: :bazel} = project, id),
    do: Bazel.get_invocation(project.id, id, include_cache_summary: false)

  def get_build(_project, _id), do: {:error, :not_found}

  @doc """
  Loads a build's timeline with its steps and the machine samples recorded
  on the build's clock.
  """
  def load(%Builds.Build{} = build) do
    metrics =
      build
      |> ClickHouseRepo.preload(:machine_metrics)
      |> Map.fetch!(:machine_metrics)
      |> Enum.filter(&is_number(&1.offset_ms))
      |> Enum.sort_by(& &1.offset_ms)

    build.id
    |> Builds.build_timeline(duration: build.duration)
    |> Map.put(:machine_metrics, metrics)
  end

  def load(%Gradle.Build{} = build), do: Gradle.Timeline.load(build)
  def load(%Mix.Build{} = build), do: Mix.Timeline.load(build)
  def load(%Bazel.Invocation{} = invocation), do: Bazel.Timeline.load(invocation)

  @doc """
  Encodes a timeline as a Chrome Trace Event JSON object.

  Steps run in parallel, and slices on one trace thread must not partially
  overlap, so steps are packed into lanes: each step goes to the first lane
  that is free when it starts, which makes the number of lanes the build's
  peak parallelism. Lanes are threads 2 and up; thread 1, which Perfetto
  treats as the process's main thread, holds one slice spanning the whole
  build. Machine samples become CPU and memory counter tracks. `metadata`
  is stored in the trace, and its `:name` names the build's process.
  """
  def encode(timeline, metadata) do
    {slices, lane_count} = lanes(timeline.events)

    lane_names =
      for lane <- 1..lane_count//1 do
        %{ph: "M", pid: 1, tid: lane + 1, name: "thread_name", args: %{name: "Lane #{lane}"}}
      end

    %{
      traceEvents:
        [
          %{ph: "M", pid: 1, name: "process_name", args: %{name: metadata.name}},
          %{ph: "M", pid: 1, tid: 1, name: "thread_name", args: %{name: "Build"}},
          %{ph: "X", pid: 1, tid: 1, name: metadata.name, cat: "build", ts: 0, dur: us(timeline.duration), args: %{}}
        ] ++ lane_names ++ slices ++ counters(Map.get(timeline, :machine_metrics, [])),
      displayTimeUnit: "ms",
      metadata: Map.put(metadata, :source, "Tuist")
    }
  end

  defp lanes(events) do
    {slices, lane_ends} =
      events
      |> Enum.sort_by(&{&1.start_ms, &1.event_id})
      |> Enum.map_reduce(%{}, fn event, lane_ends ->
        start = us(event.start_ms)
        finish = start + us(event.duration_ms)
        lane = Enum.find(1..(map_size(lane_ends) + 1), &(Map.get(lane_ends, &1, start) <= start))

        slice = %{
          ph: "X",
          pid: 1,
          tid: lane + 1,
          name: event.title,
          cat: to_string(event.category),
          ts: start,
          dur: finish - start,
          args: %{project: event.project, target: event.target, status: event.status, step_id: to_string(event.event_id)}
        }

        {slice, Map.put(lane_ends, lane, finish)}
      end)

    {slices, map_size(lane_ends)}
  end

  defp counters(samples) do
    Enum.flat_map(samples, fn sample ->
      ts = us(sample.offset_ms)

      [
        %{ph: "C", pid: 1, name: "CPU (%)", ts: ts, args: %{usage: Map.get(sample, :cpu_usage_percent, 0)}},
        %{ph: "C", pid: 1, name: "Memory (GiB)", ts: ts, args: %{used: Map.get(sample, :memory_used_bytes, 0) / @gib}}
      ]
    end)
  end

  defp us(ms), do: round(ms * 1000)

  @doc """
  Signs a token that grants read access to one build's trace for an hour,
  so agents can download it without a browser session.
  """
  def sign_token(project, build_id), do: Phoenix.Token.sign(Tuist.Web.endpoint(), @token_salt, {project.id, build_id})

  def verify_token(token) when is_binary(token) do
    case Phoenix.Token.verify(Tuist.Web.endpoint(), @token_salt, token, max_age: @token_max_age) do
      {:ok, {project_id, build_id}} -> {:ok, project_id, build_id}
      _ -> {:error, :invalid_token}
    end
  end

  def token_max_age, do: @token_max_age
end
