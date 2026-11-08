defmodule Pulse.OTLP.Metrics do
  @moduledoc "Bounded OTLP scalar and distribution metrics with complete typed source metadata."
  import Bitwise

  alias Pulse.Codec.NIF
  alias Pulse.IngestLimits
  alias Pulse.OTLP.Metrics.Distribution
  alias Pulse.OTLP.Value
  alias Pulse.Record.Exemplar
  alias Pulse.Record.MetricSample

  @kinds ~w(gauge sum histogram exponentialHistogram summary)
  @max_time 9_223_372_036_854_775_807
  @max_count 4_294_967_295
  @payload_bytes 16_777_216

  def decode(%{} = payload) do
    with :ok <- IngestLimits.validate(:otlp_metrics, payload),
         resources when is_list(resources) <- Value.field(payload, "resourceMetrics", []),
         {:ok, records, rejected, _} <- reduce(resources, {:ok, [], 0, 0}, &resource/2),
         records = Enum.reverse(records),
         {:ok, _} <- NIF.metric_metadata_size(records, @payload_bytes),
         :ok <- projection_identities(records),
         :ok <- distribution_duplicates(records) do
      {:ok, records, rejected}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_otlp}
    end
  end

  def decode(_), do: {:error, :invalid_otlp}

  def decode_protobuf(body) do
    l = IngestLimits.config()

    opts =
      {l.max_records, l.max_attributes, l.max_key_bytes, l.max_value_bytes, l.max_attribute_bytes, min(l.max_depth, 32),
       l.max_nodes, l.max_otlp_nodes}

    with {:ok, payload} <- NIF.decode_otlp_metrics(body, opts), do: decode(payload)
  end

  # A projected family must not alias a different original instrument or
  # typed owner within this request. This is validation, not a global catalog.
  defp projection_identities(records) do
    Enum.reduce_while(records, %{}, &projection_identity/2)
    |> case do
      {:error, _} = error -> error
      _ -> :ok
    end
  end

  defp projection_identity(%MetricSample{labels: labels, otlp: otlp}, seen) do
    point = otlp["point"]
    scope = otlp["scope"]

    identity =
      {otlp["metric"]["name"], otlp["metric"]["unit"], point["kind"], point["aggregationTemporality"],
       identity_attributes(otlp["resource"]), Map.take(scope, ["name", "version"]), identity_attributes(scope),
       identity_attributes(point)}

    projected? = Map.has_key?(otlp, "projection")

    case Map.get(seen, labels) do
      nil -> {:cont, Map.put(seen, labels, {identity, projected?})}
      {^identity, _} -> {:cont, seen}
      {_, previous?} when projected? or previous? -> {:halt, {:error, :invalid_otlp}}
      _ -> {:cont, seen}
    end
  end

  defp identity_attributes(owner), do: Map.new(owner["attributes"], &{&1["key"], &1["value"]})

  defp distribution_duplicates(records) do
    Enum.reduce_while(records, %{}, &distribution_duplicate/2)
    |> case do
      {:error, _} = error -> error
      _ -> :ok
    end
  end

  defp distribution_duplicate(%MetricSample{otlp: %{"projection" => _}} = sample, seen) do
    key = {sample.labels, sample.timestamp_ns}
    fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary(sample.otlp, [:deterministic]))

    case Map.fetch(seen, key) do
      :error -> {:cont, Map.put(seen, key, fingerprint)}
      {:ok, ^fingerprint} -> {:cont, seen}
      _ -> {:halt, {:error, :invalid_otlp}}
    end
  end

  defp distribution_duplicate(_, seen), do: {:cont, seen}

  defp reduce(values, initial, fun) do
    Enum.reduce_while(values, initial, fn value, acc ->
      case fun.(value, acc) do
        {:ok, _, _, _} = next -> {:cont, next}
        {:error, _} = error -> {:halt, error}
        _ -> {:halt, {:error, :invalid_otlp}}
      end
    end)
  end

  defp resource(%{} = owner, acc) do
    with {:ok, resource, typed} <- metadata(Value.field(owner, "resource", %{}), :resource),
         {:ok, schema} <- text(Value.field(owner, "schemaUrl", "")),
         scopes when is_list(scopes) <- Value.field(owner, "scopeMetrics", []) do
      reduce(scopes, acc, &scope(&1, resource, typed, schema, &2))
    end
  end

  defp resource(_, _), do: :error

  defp scope(%{} = owner, resource, typed, schema, acc) do
    with {:ok, _, scope} <- metadata(Value.field(owner, "scope", %{}), :scope),
         {:ok, scope_schema} <- text(Value.field(owner, "schemaUrl", "")),
         metrics when is_list(metrics) <- Value.field(owner, "metrics", []) do
      base = %{"resource" => typed, "resourceSchemaUrl" => schema, "scope" => scope, "scopeSchemaUrl" => scope_schema}
      reduce(metrics, acc, &metric(&1, resource, base, &2))
    end
  end

  defp scope(_, _, _, _, _), do: :error

  defp metadata(%{} = owner, kind) do
    with true <- Value.field(owner, "entityRefs", []) == [],
         {:ok, attrs, typed} <- Value.attributes(owner),
         {:ok, dropped} <- Value.integer(Value.field(owner, "droppedAttributesCount", 0), 0, @max_count) do
      complete_metadata(kind, owner, attrs, %{"attributes" => typed, "droppedAttributesCount" => dropped})
    end
  end

  defp metadata(_, _), do: :error
  defp complete_metadata(:resource, _, attrs, typed), do: {:ok, attrs, typed}

  defp complete_metadata(:scope, owner, attrs, typed) do
    with {:ok, name} <- text(Value.field(owner, "name", "")),
         {:ok, version} <- text(Value.field(owner, "version", "")),
         do: {:ok, attrs, Map.merge(typed, %{"name" => name, "version" => version})}
  end

  defp metric(%{} = owner, resource, base, {:ok, records, rejected, expanded}) do
    with [kind] <- Enum.filter(@kinds, &(Map.get(owner, &1) != nil)),
         %{} = data <- owner[kind],
         points when is_list(points) <- Value.field(data, "dataPoints", []),
         {:ok, name} <- text(Value.field(owner, "name", "")),
         true <- name != "",
         {:ok, description} <- text(Value.field(owner, "description", "")),
         {:ok, unit} <- text(Value.field(owner, "unit", "")),
         {:ok, _, typed_metadata} <- Value.attributes(%{"attributes" => Value.field(owner, "metadata", [])}) do
      descriptor = %{"name" => name, "description" => description, "unit" => unit, "metadata" => typed_metadata}
      base = Map.put(base, "metric", descriptor)
      reduce(points, {:ok, records, rejected, expanded}, &collect(&1, kind, data, resource, base, &2))
    end
  end

  defp metric(_, _, _, _), do: :error

  defp collect(point, kind, data, resource, base, {:ok, records, rejected, expanded}) do
    maximum = IngestLimits.config().max_records - expanded

    case point(point, kind, data, resource, base, maximum) do
      {:ok, %MetricSample{} = sample} -> collect_samples([sample], records, rejected, expanded)
      {:ok, samples} when is_list(samples) -> collect_samples(samples, records, rejected, expanded)
      {:error, _} = error -> error
      _ -> {:ok, records, rejected + 1, expanded}
    end
  end

  defp collect_samples(samples, records, rejected, expanded) do
    size = expanded + length(samples)

    if size <= IngestLimits.config().max_records,
      do: {:ok, Enum.reverse(samples, records), rejected, size},
      else: {:error, :too_many_records}
  end

  # Unsupported types and unspecified temporality are explicit rejected data
  # points; they never become invented gauges or empty successes. Delta points
  # are stored as reported, never accumulated: instances share no per-series
  # state. A monotonic delta is not named `_total`, so it is not mistaken for
  # a cumulative counter; query it with `sum_over_time`.
  defp point(%{} = point, kind, data, resource, base, _maximum) when kind in ["gauge", "sum"] do
    with {:ok, temporality, monotonic} <- aggregation(kind, data),
         {:ok, time} <- Value.integer(Value.field(point, "timeUnixNano", 0), 1, @max_time),
         {:ok, start} <- Value.integer(Value.field(point, "startTimeUnixNano", 0), 0, time),
         {:ok, flags} <- Value.integer(Value.field(point, "flags", 0), 0, @max_count),
         {:ok, value, typed_value} <- number(point, flags),
         true <- not monotonic or value in [:nan, :infinity, :stale] or (is_number(value) and value >= 0),
         {:ok, exemplars, prometheus} <- exemplars(Value.field(point, "exemplars", [])),
         {:ok, attrs, typed_attrs} <- Value.attributes(point),
         {:ok, labels} <- labels(attrs, resource, base["scope"], base["metric"]["name"], monotonic and temporality == 2),
         :ok <- label_budget(labels) do
      source = %{
        "kind" => kind,
        "aggregationTemporality" => temporality,
        "isMonotonic" => monotonic,
        "timeUnixNano" => Integer.to_string(time),
        "startTimeUnixNano" => Integer.to_string(start),
        "flags" => flags,
        "attributes" => typed_attrs,
        "exemplars" => exemplars
      }

      source = Map.merge(source, typed_value)

      {:ok,
       %MetricSample{
         timestamp_ns: time,
         value: value,
         labels: labels,
         otlp: Map.put(base, "point", source),
         exemplars: if(prometheus != [], do: prometheus)
       }}
    end
  end

  defp point(%{} = point, kind, data, resource, base, maximum)
       when kind in ["histogram", "exponentialHistogram", "summary"] do
    with {:ok, time} <- Value.integer(Value.field(point, "timeUnixNano", 0), 1, @max_time),
         {:ok, start} <- Value.integer(Value.field(point, "startTimeUnixNano", 0), 0, time),
         {:ok, flags} <- Value.integer(Value.field(point, "flags", 0), 0, @max_count),
         {:ok, attrs, typed_attrs} <- Value.attributes(point),
         {:ok, labels} <- labels(attrs, resource, base["scope"], base["metric"]["name"], false),
         false <- Map.has_key?(labels, if(kind == "summary", do: "quantile", else: "le")),
         {:ok, fields, projections} <- Distribution.normalize(kind, data, point, maximum, band(flags, 1) == 1),
         {:ok, exemplars, prometheus} <-
           exemplars(if(kind == "summary", do: [], else: Value.field(point, "exemplars", []))) do
      source =
        Map.merge(fields, %{
          "kind" => kind,
          "timeUnixNano" => Integer.to_string(time),
          "startTimeUnixNano" => Integer.to_string(start),
          "flags" => flags,
          "attributes" => typed_attrs
        })

      source = if kind == "summary", do: source, else: Map.put(source, "exemplars", exemplars)
      hosts = bucket_exemplars(projections, prometheus)
      distribution_samples(projections, labels, time, flags, Map.put(base, "point", source), hosts)
    end
  end

  defp point(_, _, _, _, _, _), do: :error

  defp distribution_samples(projections, labels, time, flags, source, hosts) do
    # Share each derived name across its buckets/quantiles. Otherwise a long
    # descriptor name would be copied once per row before the byte proof.
    names = Map.new(["_bucket", "_count", "_sum"], &{&1, labels["__name__"] <> &1})
    names = Map.put(names, "", labels["__name__"])

    Enum.reduce_while(projections, {:ok, []}, fn {suffix, label, value, component}, {:ok, rows} ->
      projected = Map.put(labels, "__name__", Map.fetch!(names, suffix))
      projected = if label, do: Map.put(projected, elem(label, 0), elem(label, 1)), else: projected

      case label_budget(projected) do
        :ok ->
          projection = projection_metadata(component, label)

          sample = %MetricSample{
            timestamp_ns: time,
            value: sample_value(value, flags),
            labels: projected,
            otlp: Map.put(source, "projection", projection),
            exemplars: Map.get(hosts, label)
          }

          {:cont, {:ok, [sample | rows]}}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      other -> other
    end
  end

  # As Prometheus' OTLP translator does, each exemplar goes to the first
  # `_bucket` series whose `le` bound holds its value; NaN goes nowhere.
  defp bucket_exemplars(_projections, []), do: %{}

  defp bucket_exemplars(projections, exemplars) do
    buckets =
      projections
      |> Enum.flat_map(fn
        {"_bucket", {"le", le} = label, _value, _component} -> [{bound(le), label}]
        _ -> []
      end)
      |> Enum.sort()

    exemplars
    |> Enum.group_by(&holding_bucket(buckets, &1.value))
    |> Map.delete(nil)
  end

  defp holding_bucket(buckets, value) do
    Enum.find_value(buckets, fn {bound, label} -> if at_most?(value, bound), do: label end)
  end

  defp bound("+Inf"), do: :infinity
  defp bound(le), do: le |> Float.parse() |> elem(0)

  defp at_most?(:nan, _bound), do: false
  defp at_most?(_value, :infinity), do: true
  defp at_most?(:infinity, _bound), do: false
  defp at_most?(:negative_infinity, _bound), do: true
  defp at_most?(value, bound), do: value <= bound

  defp projection_metadata(component, nil), do: %{"component" => component}
  defp projection_metadata(component, {name, value}), do: %{"component" => component, name => value}

  defp aggregation("gauge", _), do: {:ok, 0, false}

  defp aggregation("sum", data) do
    with {:ok, temporality} when temporality in [1, 2] <-
           Value.integer(Value.field(data, "aggregationTemporality", 0), 0, 2),
         monotonic when is_boolean(monotonic) <- Value.field(data, "isMonotonic", false) do
      {:ok, temporality, monotonic}
    else
      _ -> :error
    end
  end

  defp number(point, flags) do
    assigned = Enum.filter(~w(asInt asDouble), &(Map.get(point, &1) != nil))

    case assigned do
      [] when band(flags, 1) == 1 ->
        {:ok, :stale, %{}}

      ["asInt"] ->
        with {:ok, int} <- Value.integer(point["asInt"], -@max_time - 1, @max_time) do
          {:ok, sample_value(int / 1, flags), %{"asInt" => Integer.to_string(int)}}
        end

      ["asDouble"] ->
        with {:ok, value, %{"doubleValue" => typed}} <- Value.decode(%{"doubleValue" => point["asDouble"]}) do
          {:ok, sample_value(ieee(value), flags), %{"asDouble" => typed}}
        end

      _ ->
        :error
    end
  end

  defp sample_value(value, flags), do: if(band(flags, 1) == 1, do: :stale, else: value)

  # Exemplars are source metadata, not additional Prometheus samples. Keeping
  # them does not discard the scalar whenever an SDK records inside a span.
  # Each source exemplar is kept typed, and also as a Prometheus exemplar
  # when its label set fits Prometheus' limit.
  defp exemplars(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, [], []}, fn value, {:ok, typed, prometheus} ->
      case exemplar(value) do
        {:ok, source, nil} -> {:cont, {:ok, [source | typed], prometheus}}
        {:ok, source, exemplar} -> {:cont, {:ok, [source | typed], [exemplar | prometheus]}}
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, typed, prometheus} -> {:ok, Enum.reverse(typed), Enum.reverse(prometheus)}
      other -> other
    end
  end

  defp exemplars(_), do: :error

  defp exemplar(%{} = value) do
    with {:ok, time} <- Value.integer(Value.field(value, "timeUnixNano", 0), 1, @max_time),
         {:ok, sample, number} <- number(value, 0),
         {:ok, plain, attrs} <- Value.attributes(%{"attributes" => Value.field(value, "filteredAttributes", [])}),
         {:ok, trace} <- context(Value.field(value, "traceId", ""), 32),
         {:ok, span} <- context(Value.field(value, "spanId", ""), 16) do
      typed =
        Map.merge(number, %{
          "timeUnixNano" => Integer.to_string(time),
          "filteredAttributes" => attrs,
          "traceId" => trace,
          "spanId" => span
        })

      {:ok, typed, prometheus_exemplar(plain, trace, span, sample, time)}
    end
  end

  defp exemplar(_), do: :error

  # Prometheus' OTLP translation: filtered attributes as labels, plus
  # `trace_id` and `span_id` unless empty or zero.
  defp prometheus_exemplar(attrs, trace, span, value, time) do
    case project_attributes(attrs) do
      {:ok, labels} ->
        labels = labels |> put_context("trace_id", trace) |> put_context("span_id", span)
        length = Enum.reduce(labels, 0, fn {k, v}, n -> n + String.length(k) + String.length(v) end)
        if length <= Exemplar.max_label_set_length(), do: %Exemplar{labels: labels, value: value, timestamp_ns: time}

      _ ->
        nil
    end
  end

  defp put_context(labels, key, id) do
    if id == "" or String.trim(id, "0") == "", do: labels, else: Map.put(labels, key, id)
  end

  defp context("", _), do: {:ok, ""}

  defp context(value, size) when is_binary(value) and byte_size(value) == size do
    case Base.decode16(value, case: :mixed) do
      # IDs are retained source metadata, not a promise of valid span context.
      # Some always-on exemplar exporters supply zero IDs outside a span.
      {:ok, bytes} ->
        {:ok, Base.encode16(bytes, case: :lower)}

      _ ->
        :error
    end
  end

  defp context(_, _), do: :error

  defp ieee("NaN"), do: :nan
  defp ieee("Infinity"), do: :infinity
  defp ieee("-Infinity"), do: :negative_infinity
  defp ieee(value), do: value

  defp labels(attrs, resource, scope, name, monotonic) do
    name = normalize_name(name, true)
    name = if monotonic and not String.ends_with?(name, "_total"), do: name <> "_total", else: name

    with {:ok, labels} <- project_attributes(attrs),
         {:ok, labels} <- promote(labels, "job", job(resource)),
         {:ok, labels} <- promote(labels, "instance", resource["service.instance.id"]),
         {:ok, labels} <- promote(labels, "otel_scope_name", scope["name"]),
         {:ok, labels} <- promote(labels, "otel_scope_version", scope["version"]),
         false <- Map.has_key?(labels, "__name__") do
      {:ok, Map.put(labels, "__name__", name)}
    end
  end

  defp project_attributes(attrs) do
    Enum.reduce_while(attrs, {:ok, %{}}, fn {key, value}, {:ok, labels} ->
      normalized = normalize_name(key, false)

      if Map.has_key?(labels, normalized),
        do: {:halt, :error},
        else: {:cont, {:ok, Map.put(labels, normalized, label_value(value))}}
    end)
  end

  defp normalize_name(name, metric?) do
    name = String.replace(name, if(metric?, do: ~r/[^a-zA-Z0-9_:]/u, else: ~r/[^a-zA-Z0-9_]/u), "_")
    if String.match?(name, ~r/^[0-9]/), do: "_" <> name, else: name
  end

  defp promote(labels, _, value) when value in [nil, ""], do: {:ok, labels}

  defp promote(labels, key, value) when is_binary(value) do
    if Map.has_key?(labels, key) and labels[key] != value, do: :error, else: {:ok, Map.put(labels, key, value)}
  end

  defp promote(_, _, _), do: :error

  defp job(%{"service.name" => name, "service.namespace" => ns}) when is_binary(name) and is_binary(ns) and ns != "",
    do: ns <> "/" <> name

  defp job(resource), do: resource["service.name"]
  defp label_value(value) when is_binary(value), do: value
  defp label_value(value), do: Pulse.JSON.encode!(value)

  defp label_budget(labels) do
    l = IngestLimits.config()

    if map_size(labels) > l.max_attributes or
         Enum.any?(labels, fn {k, v} -> byte_size(k) > l.max_key_bytes or byte_size(v) > l.max_value_bytes end) or
         Enum.reduce(labels, 0, fn {k, v}, n -> n + byte_size(k) + byte_size(v) end) > l.max_attribute_bytes,
       do: {:error, :attributes_too_large},
       else: :ok
  end

  defp text(value) when is_binary(value), do: {:ok, Pulse.JSON.detach(value)}
  defp text(_), do: :error
end
