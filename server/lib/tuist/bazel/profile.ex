defmodule Tuist.Bazel.Profile do
  @moduledoc """
  Ingests Bazel's JSON trace profile independently of its bounded BEP summary.
  Whole profiles are validated before persistence; events are never ranked or truncated.
  """
  use Ecto.Schema

  import Ecto.Query

  alias Tuist.Bazel.Action
  alias Tuist.Bazel.ProfileDecoder
  alias Tuist.Bazel.ProfileSteps
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Tests.Sanitizer

  @max_compressed_bytes 32 * 1024 * 1024
  @max_expanded_bytes 128 * 1024 * 1024
  @max_events 1_000_000
  # CollectLocalResourceUsage aggregates counters into one-second TimeSeries buckets.
  @metric_bucket_ms 1000
  @metric_names %{
    "CPU usage (total)" => {:cpu_usage_cores, 1, "system cpu"},
    "Memory usage (total)" => {:memory_used_bytes, 1024 * 1024, "system memory"},
    "Network Up usage (total)" => {:network_bytes_out, 1_000_000 / 8, "system network up (Mbps)"},
    "Network Down usage (total)" => {:network_bytes_in, 1_000_000 / 8, "system network down (Mbps)"}
  }

  @payload_keys Map.new(
                  ~w(events total_count duration target_count machine_metrics has_metrics local_navigation logs_available time_origin profile_started_at_ms coverage steps_version event_id title project target primary_output category start_ms duration_ms status offset_ms cpu_usage_cores cpu_usage_percent memory_used_bytes network_bytes_in network_bytes_out action_started_at_ms)a,
                  &{Atom.to_string(&1), &1}
                )

  @primary_key false
  schema "bazel_profiles" do
    field :project_id, Ch, type: "Int64"
    field :invocation_id, Ch, type: "String"
    field :payload, Ch, type: "String"
    field :inserted_at, Ch, type: "DateTime"
  end

  def ingest(project, invocation_id, compressed) do
    with {:ok, profile} <- decode(compressed),
         {:ok, timeline} <- normalize(profile, invocation_id, project.name) do
      version = Base.encode16(:crypto.hash(:sha256, compressed), case: :lower)
      ProfileSteps.insert(project, invocation_id, version, timeline)
      timeline = timeline |> Map.put(:steps_version, version) |> Map.put(:events, [])

      IngestRepo.insert_all(__MODULE__, [
        %{
          project_id: project.id,
          invocation_id: invocation_id,
          payload: JSON.encode!(timeline),
          inserted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
        }
      ])

      :ok
    end
  end

  def load(invocation, opts \\ [])
  def load(%{project_id: nil}, _opts), do: nil
  def load(%{invocation_id: nil}, _opts), do: nil

  def load(invocation, opts) do
    payload =
      ClickHouseRepo.one(
        from(p in __MODULE__,
          where: p.project_id == ^invocation.project_id and p.invocation_id == ^invocation.invocation_id,
          order_by: [desc: p.inserted_at],
          limit: 1,
          select: p.payload
        )
      )

    if payload do
      {timeline, nil, ""} =
        JSON.decode(payload, nil,
          object_push: fn key, value, acc ->
            case @payload_keys[key] do
              nil -> acc
              known -> [{known, value} | acc]
            end
          end
        )

      timeline = timeline |> with_metric_intervals() |> with_cpu_percentage(invocation.custom_values)

      if Keyword.get(opts, :include_steps, true) do
        if timeline[:steps_version] do
          events = ProfileSteps.events(invocation, timeline.steps_version)
          %{timeline | events: events, logs_available: Enum.any?(events, &(&1.status != "unknown"))}
        else
          Action.enrich(timeline, invocation)
        end
      else
        Map.drop(timeline, [:events, :total_count, :target_count])
      end
    end
  end

  def available?(invocation) do
    metadata =
      ClickHouseRepo.one(
        from(p in __MODULE__,
          where: p.project_id == ^invocation.project_id and p.invocation_id == ^invocation.invocation_id,
          order_by: [desc: p.inserted_at],
          limit: 1,
          select: %{
            version: fragment("JSONExtractString(?, 'steps_version')", p.payload),
            events: fragment("JSONLength(?, 'events')", p.payload),
            metrics: fragment("JSONLength(?, 'machine_metrics')", p.payload)
          }
        )
      )

    case metadata do
      nil ->
        nil

      %{version: "", events: count, metrics: metrics} ->
        count > 0 or (metrics > 0 and load(invocation, include_steps: false).has_metrics)

      %{version: version, metrics: metrics} ->
        ProfileSteps.available?(invocation, version) or
          (metrics > 0 and load(invocation, include_steps: false).has_metrics)
    end
  end

  def steps_version(%{project_id: nil}), do: nil
  def steps_version(%{invocation_id: nil}), do: nil

  def steps_version(invocation) do
    ClickHouseRepo.one(
      from(p in __MODULE__,
        where: p.project_id == ^invocation.project_id and p.invocation_id == ^invocation.invocation_id,
        order_by: [desc: p.inserted_at],
        limit: 1,
        select: fragment("JSONExtractString(?, 'steps_version')", p.payload)
      )
    )
  end

  def decode(compressed) when is_binary(compressed) and byte_size(compressed) <= @max_compressed_bytes do
    z = :zlib.open()

    try do
      :ok = :zlib.inflateInit(z, 31)

      case inflate(z, compressed, [], 0) do
        {:ok, json} ->
          :ok = :zlib.inflateEnd(z)
          ProfileDecoder.decode(json)

        error ->
          error
      end
    rescue
      _ -> {:error, :invalid_profile}
    after
      :zlib.close(z)
    end
  end

  def decode(_), do: {:error, :profile_too_large}

  defp inflate(z, input, chunks, size) do
    {status, output} = :zlib.safeInflate(z, input)
    size = size + IO.iodata_length(output)

    cond do
      size > @max_expanded_bytes -> {:error, :profile_too_large}
      status == :finished -> {:ok, IO.iodata_to_binary(Enum.reverse([output | chunks]))}
      true -> inflate(z, <<>>, [output | chunks], size)
    end
  end

  def normalize(%{"otherData" => %{"build_id" => id} = metadata, "traceEvents" => events}, id, project)
      when is_list(events) and length(events) <= @max_events do
    steps =
      events
      |> Enum.with_index()
      |> Enum.flat_map(fn {event, index} -> step(event, index, project) end)
      |> Enum.sort_by(&{&1.start_ms, &1.event_id})

    samples =
      events
      |> Enum.reduce(%{}, &metric/2)
      |> Map.values()
      |> Enum.sort_by(& &1.offset_ms)
      |> without_empty_trailing_buckets()

    duration = Enum.reduce(steps, 1, &max(&2, &1.start_ms + &1.duration_ms))
    duration = Enum.reduce(samples, duration, &max(&2, &1.offset_ms))

    {:ok,
     with_metric_intervals(%{
       events: steps,
       total_count: length(steps),
       duration: duration,
       target_count: steps |> Enum.reject(&(&1.target == "")) |> Enum.uniq_by(&{&1.project, &1.target}) |> length(),
       machine_metrics: samples,
       has_metrics: samples != [],
       local_navigation: true,
       logs_available: false,
       time_origin: "profile_start",
       profile_started_at_ms: epoch(metadata["profile_start_ts"]),
       coverage: "trace_profile"
     })}
  end

  def normalize(_, _, _), do: {:error, :invalid_profile}

  defp with_cpu_percentage(timeline, metadata) do
    # Native bucket sums can exceed capacity by floating-point rounding alone.
    # Tolerate that error without accepting a materially inconsistent CPU count.
    with value when is_binary(value) <- (metadata || %{})["TUIST_CPU_COUNT"],
         {count, ""} when count > 0 and count <= 65_536 <- Integer.parse(value),
         true <- Enum.all?(timeline.machine_metrics, &(Map.get(&1, :cpu_usage_cores, 0) <= count + 1.0e-9)) do
      samples =
        Enum.map(timeline.machine_metrics, fn
          %{cpu_usage_cores: cores} = sample -> Map.put(sample, :cpu_usage_percent, min(cores / count * 100, 100.0))
          sample -> sample
        end)

      Map.put(timeline, :machine_metrics, samples)
    else
      _ -> timeline
    end
  end

  defp with_metric_intervals(timeline) do
    samples =
      timeline.machine_metrics
      |> without_empty_trailing_buckets()
      |> Enum.map(fn sample ->
        Map.put(sample, :duration_ms, min(@metric_bucket_ms, max(0, timeline.duration - sample.offset_ms)))
      end)

    timeline |> Map.put(:machine_metrics, samples) |> Map.put(:has_metrics, samples != [])
  end

  defp without_empty_trailing_buckets(samples) do
    # Bazel pads exported time series with zeros. Zero host memory distinguishes
    # empty buckets from legitimate idle CPU or network measurements.
    samples
    |> Enum.reverse()
    |> Enum.drop_while(fn sample ->
      sample[:memory_used_bytes] == 0 and
        Enum.all?(@metric_names, fn {_name, {field, _multiplier, _key}} -> Map.get(sample, field, 0) == 0 end)
    end)
    |> Enum.reverse()
  end

  defp step(%{"ph" => "X", "ts" => ts, "dur" => duration, "name" => name} = event, index, project)
       when is_number(ts) and ts >= 0 and is_number(duration) and duration > 0 and is_binary(name) do
    args = if is_map(event["args"]), do: event["args"], else: %{}

    [
      %{
        event_id: "profile:#{index}",
        title: Sanitizer.sanitize(name),
        project: project,
        target: string(args["target"]),
        primary_output: string(args["out"] || event["out"]),
        category: string(args["mnemonic"] || event["cat"]),
        start_ms: ts / 1000,
        duration_ms: duration / 1000,
        status: "unknown"
      }
    ]
  end

  defp step(_, _, _), do: []

  defp metric(%{"ph" => "C", "name" => name, "ts" => ts, "args" => args}, samples)
       when is_number(ts) and ts >= 0 and is_map(args) do
    with {field, multiplier, key} <- @metric_names[name],
         value when is_number(value) and value >= 0 <- args[key] do
      offset = ts / 1000
      sample = samples |> Map.get(offset, %{offset_ms: offset}) |> Map.put(field, value * multiplier)
      Map.put(samples, offset, sample)
    else
      _ -> samples
    end
  end

  defp metric(_, samples), do: samples
  defp epoch(value) when is_integer(value) and value >= 0 and value <= 18_446_744_073_709_551_615, do: value
  defp epoch(_), do: nil
  defp string(value) when is_binary(value), do: value
  defp string(_), do: ""
end
