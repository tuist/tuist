defmodule Pulse.Alerting.Recording do
  @moduledoc "Bounded native recording results and replay of committed, immutable publication intents."

  alias Pulse.Alerting.{Canonical, Repository, Rule}
  alias Pulse.PromQL.FloatParser
  alias Pulse.Record.MetricSample
  alias Pulse.Storage
  alias Pulse.Storage.S3

  # Single rules keep their original 64 KiB intent. Both a fresh set and
  # retirement of that set must fit half the joint budget, so a future tick can
  # replace every series without getting stuck retrying an individually valid
  # set plus oversized prior stale markers. Groups share one larger intent and
  # one metric segment per tick, so their bounds are per group, not per rule.
  @single %{samples: 128, set: div(65_536 - 2048, 2), joint: 65_536 - 2048}
  @group %{samples: 4096, set: 393_216, joint: 1_048_576 - 65_536}
  @max_samples @group.samples

  @doc false
  def limits("promql_recording_group"), do: @group
  def limits(_), do: @single

  def result(rule, samples, timestamp), do: result(rule, samples, timestamp, @single)

  defp result(rule, samples, timestamp, limits) do
    with true <- is_integer(timestamp) and timestamp in 0..9_223_372_036_854_775_807,
         true <- is_list(samples) and length(samples) <= limits.samples,
         {:ok, points} <- points(rule, samples),
         result = %{"timestamp_ns" => Integer.to_string(timestamp), "samples" => points},
         :ok <- set_bounds(points, timestamp, limits) do
      {:ok, result}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_recording_result}
    end
  end

  defp set_bounds(points, timestamp, limits) do
    result = %{"timestamp_ns" => Integer.to_string(timestamp), "samples" => points}
    markers = retirement(Enum.map(points, & &1["labels"]), timestamp) |> Map.delete("next_series")

    if byte_size(Canonical.encode(result)) <= limits.set and byte_size(Canonical.encode(markers)) <= limits.set,
      do: :ok,
      else: {:error, :invalid_recording_result}
  end

  def transition(rule, samples, timestamp, previous) do
    with {:ok, result} <- result(rule, samples, timestamp),
         true <- previous?(previous, @single) do
      finish(result["samples"], Enum.map(result["samples"], & &1["labels"]), timestamp, previous, @single)
    else
      {:error, _} = error -> error
      _ -> {:error, :integrity_error}
    end
  end

  @doc """
  The rule's final points for one group member: `{"name": record, ...}`
  shaped like a single recording, so identity and value rules are identical.
  """
  def group_points(%{"record" => record, "labels" => labels}, samples) when is_list(samples) do
    if length(samples) <= @group.samples,
      do: points(%{"name" => record, "labels" => labels}, samples),
      else: {:error, :invalid_recording_result}
  end

  @doc """
  One publication for a whole group tick. `outcomes` holds, in rule order,
  `{record, {:ok, points}}` or `{record, {:error, code}}`. As in Prometheus, a
  failed rule writes nothing and marks nothing stale: its previous series stay
  current until a later successful tick drops them. Bounds apply to the group.
  """
  def group_transition(outcomes, timestamp, previous) do
    failed = MapSet.new(for {record, {:error, _}} <- outcomes, do: record)

    points =
      Enum.flat_map(outcomes, fn {_, outcome} -> if match?({:ok, _}, outcome), do: elem(outcome, 1), else: [] end)

    carried = Enum.filter(previous, &MapSet.member?(failed, &1["__name__"]))

    with true <- previous?(previous, @group),
         true <- length(points) <= @group.samples,
         points = Enum.sort_by(points, &Canonical.encode(&1["labels"])),
         :ok <- set_bounds(points, timestamp, @group),
         next = Enum.map(points, & &1["labels"]) ++ carried,
         true <- length(next) <= @group.samples,
         :ok <- set_bounds(Enum.map(next, &%{"labels" => &1, "value" => "0"}), timestamp, @group) do
      with {:ok, result} <- finish(points, next, timestamp, previous, @group),
           do: {:ok, Map.put(result, "rule_health", Enum.map(outcomes, &rule_health/1))}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_recording_result}
    end
  end

  defp rule_health({record, {:ok, []}}), do: %{"record" => record, "health" => "no_data", "series" => 0}
  defp rule_health({record, {:ok, points}}), do: %{"record" => record, "health" => "ok", "series" => length(points)}
  defp rule_health({record, {:error, code}}), do: %{"record" => record, "health" => "error", "error" => code}

  defp previous?(previous, limits),
    do: is_list(previous) and length(previous) <= limits.samples and Enum.all?(previous, &Rule.labels?/1)

  defp finish(points, next, timestamp, previous, limits) do
    next_set = MapSet.new(next)
    missing = Enum.reject(previous, &MapSet.member?(next_set, &1))
    markers = Enum.map(missing, &%{"labels" => &1, "value" => "NaN", "stale" => true})

    result = %{
      "timestamp_ns" => Integer.to_string(timestamp),
      "samples" => points ++ markers,
      "next_series" => next
    }

    if byte_size(Canonical.encode(Map.delete(result, "next_series"))) <= limits.joint,
      do: {:ok, result},
      else: {:error, :invalid_recording_result}
  end

  @doc """
  What one group member appends at `timestamp`, as Prometheus's rule group does
  before evaluating the next rule: its points, plus stale markers for its own
  previous series that disappeared. Later rules read these as stored samples.
  """
  def overlay(record, points, timestamp, previous) do
    current = MapSet.new(points, & &1["labels"])

    markers =
      for labels <- previous,
          labels["__name__"] == record,
          not MapSet.member?(current, labels),
          do: %{"labels" => labels, "value" => "NaN", "stale" => true}

    case points ++ markers do
      [] ->
        []

      samples ->
        {:ok, records} =
          records(%{"schema_version" => 1, "timestamp_ns" => Integer.to_string(timestamp), "samples" => samples})

        records
    end
  end

  def retirement(previous, timestamp) do
    %{
      "timestamp_ns" => Integer.to_string(timestamp),
      "samples" => Enum.map(previous, &%{"labels" => &1, "value" => "NaN", "stale" => true}),
      "next_series" => []
    }
  end

  defp points(rule, samples) do
    Enum.reduce_while(samples, {:ok, %{}}, fn sample, {:ok, acc} ->
      with %{"metric" => labels, "value" => [_time, value]} <- sample,
           true <- Rule.labels?(labels) and Enum.all?(Map.keys(labels), &Rule.label_name?/1),
           {:ok, _} <- FloatParser.parse(value),
           labels = labels(labels, rule),
           true <- Rule.labels?(labels),
           key = Canonical.encode(labels),
           false <- Map.has_key?(acc, key) do
        {:cont, {:ok, Map.put(acc, key, %{"labels" => labels, "value" => value})}}
      else
        true -> {:halt, {:error, :duplicate_recording_label_sets}}
        _ -> {:halt, {:error, :invalid_recording_result}}
      end
    end)
    |> case do
      {:ok, points} -> {:ok, points |> Enum.sort() |> Enum.map(&elem(&1, 1))}
      error -> error
    end
  end

  defp labels(labels, rule) do
    labels
    |> Map.merge(rule["labels"])
    |> Map.reject(fn {_key, item} -> item == "" end)
    |> Map.put("__name__", rule["name"])
  end

  @doc "Publish at most one previously committed intent. Disabled/deleted rules still drain acknowledged work."
  def publish_one(tenant, id, opts \\ []) do
    with {:ok, head, _} <- Repository.load(tenant, id, opts) do
      case Map.get(head, "recording_queue", []) do
        [] ->
          {:ok, :idle}

        [ref | _] ->
          publish_checked(tenant, id, ref, opts)
      end
    end
  end

  defp publish_checked(tenant, id, ref, opts) do
    case publish(tenant, id, ref, opts) do
      {:error, reason} = error ->
        Repository.recording_error(tenant, id, ref, error_code(reason), opts)
        error

      result ->
        result
    end
  end

  @doc """
  Drain at most eight results or two seconds (`:drain_ms`) of new work; each
  publication is independently durable.
  """
  def drain(tenant, id, opts \\ []) do
    drain(tenant, id, opts, 8, System.monotonic_time(:millisecond) + Keyword.get(opts, :drain_ms, 2000), 0)
  end

  defp drain(_tenant, _id, _opts, 0, _deadline, count), do: {:ok, count}

  defp drain(tenant, id, opts, remaining, deadline, count) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:ok, count}
    else
      case publish_one(tenant, id, opts) do
        {:ok, :idle} -> {:ok, count}
        {:ok, _} -> drain(tenant, id, opts, remaining - 1, deadline, count + 1)
        error -> error
      end
    end
  end

  defp error_code(reason)
       when reason in [
              :integrity_error,
              :committed_object_unavailable,
              :unsupported_recording_storage,
              :retention_migration_required,
              :retention_capacity,
              :timestamp_too_new,
              :recording_conflict,
              :keyed_content_mismatch
            ], do: Atom.to_string(reason)

  defp error_code(_), do: "storage_unavailable"

  defp publish(tenant, id, ref, opts) do
    with {:ok, object} <- Repository.recording_object(tenant, id, ref, opts),
         {:ok, records} <- records(object) do
      case append(tenant, records, "pulse-recording-v1-" <> ref["digest"], opts) do
        :ok -> acknowledge(tenant, id, ref, object, "published", opts)
        {:error, :retention_expired} -> acknowledge(tenant, id, ref, object, "expired", opts)
        error -> error
      end
    end
  end

  @doc false
  def state_classification(head) do
    retained? =
      Map.get(head, "recording_queue", []) != [] or Map.get(head, "recording_series", []) != [] or
        not is_nil(head["recording_last"]) or not is_nil(head["recording_error"]) or
        Map.get(head, "recording_fence_ns", "-1") != "-1"

    if retained?, do: Enum.uniq(["alert:record" | head["classification"]]), else: head["classification"]
  end

  @doc false
  def event_classification(%{"type" => "recording_expired"} = event),
    do: Enum.uniq(["alert:record" | event["classification"]])

  def event_classification(event), do: event["classification"]

  defp acknowledge(tenant, id, ref, object, status, opts) do
    progress = %{"status" => status, "timestamp_ns" => object["timestamp_ns"], "digest" => ref["digest"]}

    event =
      if status == "expired" do
        %{
          "type" => "recording_expired",
          "recording" => ref,
          "revision" => object["revision"],
          "classification" => ["alert:record"],
          "timestamp_ns" => Integer.to_string(System.system_time(:nanosecond)),
          "actor" => %{"id" => "pulse-recording-publisher", "type" => "service"}
        }
      end

    with :ok <-
           Repository.ack_recording(
             tenant,
             id,
             ref,
             Keyword.merge(opts, recording_progress: progress, recording_event: event)
           ),
         do: {:ok, if(status == "expired", do: :expired, else: :published)}
  end

  defp records(%{"schema_version" => 1, "timestamp_ns" => timestamp, "samples" => samples})
       when is_binary(timestamp) and is_list(samples) and (is_list(samples) and samples != []) and
              length(samples) <= @max_samples * 2 do
    with {ns, ""} <- Integer.parse(timestamp),
         true <- ns in 0..9_223_372_036_854_775_807 do
      Enum.reduce_while(samples, {:ok, []}, &record(&1, &2, ns))
      |> case do
        {:ok, records} -> {:ok, Enum.reverse(records)}
        error -> error
      end
    else
      _ -> {:error, :integrity_error}
    end
  end

  defp records(_), do: {:error, :integrity_error}

  defp record(point, {:ok, acc}, ns) do
    with %{"labels" => labels, "value" => value} <- point,
         true <- Rule.labels?(labels),
         {:ok, number} <- number(point, value) do
      {:cont, {:ok, [%MetricSample{labels: labels, timestamp_ns: ns, value: number} | acc]}}
    else
      _ -> {:halt, {:error, :integrity_error}}
    end
  end

  defp number(%{"stale" => true}, "NaN"), do: {:ok, :stale}
  defp number(%{"stale" => _}, _), do: :error
  defp number(_point, value), do: FloatParser.parse(value)

  defp append(tenant, records, key, opts) do
    # Only the durable, keyed adapter is supported in production. Test injection
    # is private to callers, never a rule field, binding, API argument or URL.
    case Keyword.get(opts, :recording_append) do
      fun when is_function(fun, 3) ->
        fun.(tenant, records, idempotency_key: key)

      nil ->
        if Storage.adapter() == S3,
          do: Storage.append(:metrics, tenant, records, idempotency_key: key),
          else: {:error, :unsupported_recording_storage}
    end
  catch
    _, _ -> {:error, :storage_unavailable}
  end
end
