defmodule Pulse.LogQL.Entry do
  @moduledoc """
  A single log line as it moves through the LogQL pipeline.

    * `timestamp_ns` — original ingest timestamp (never mutated).
    * `line` — the *current* text of the log entry. `line_format`,
      `decolorize`, and `unpack` rewrite it in place. Downstream parsers
      that key off the line (`json`, `logfmt`, `regexp`, `pattern`) read
      whatever the previous stages left here.
    * `labels` — the merged label bag. Starts as `resource ∪ attributes`
      plus synthetic promoted fields (`service`, `service_name`,
      `level`, `detected_level`) derived from the typed struct fields,
      so `{service_name="api"}` and `{service="api"}` both match
      regardless of which ingest path produced the record.
    * `base_labels` — resource/promoted stream names still protected from
      parser writes. Drop/rename releases a name. Manual entries without
      provenance treat all initial labels as stream labels.
    * `metadata_labels` — protected structured-metadata names, including the
      one-suffix names of metadata that collided with stream labels. Incoming
      error labels stay protected but use the parsed category on the wire.
    * `extracted_labels` — names written by earlier parsed stages, including
      names subsequently dropped. Ordinary parsers keep the first extraction;
      explicit expression parsers have their own overwrite rules.
    * `label_categories` — optional current name-to-origin map for negotiated
      categorized HTTP output. Mutations update it alongside `labels`, even
      when the new value equals the old one. Never inferred from final values.
    * `error_labels` — authoritative pipeline error and details, independent
      of ordinary labels with those names. `labels` overlays these for output
      and templates. `ordinary_error_labels` retains only the two shadowed
      ordinary values/categories, including values revealed by error resets.
  """

  alias Pulse.Record.Log

  @enforce_keys [:timestamp_ns, :line, :labels]
  defstruct [
    :timestamp_ns,
    :line,
    :labels,
    :base_labels,
    :label_categories,
    :error_labels,
    ordinary_error_labels: %{},
    metadata_labels: %{},
    extracted_labels: %{}
  ]

  @type category :: :stream | :structured_metadata | :parsed
  @type t :: %__MODULE__{
          timestamp_ns: non_neg_integer() | nil,
          line: String.t(),
          labels: %{optional(String.t()) => String.t()},
          base_labels: map() | nil,
          label_categories: %{optional(String.t()) => category()} | nil,
          error_labels: map() | nil,
          ordinary_error_labels: map(),
          metadata_labels: map(),
          extracted_labels: %{optional(String.t()) => true}
        }

  @spec from_record(Log.t(), boolean()) :: t()
  def from_record(%Log{} = record, categorize_labels? \\ false) do
    # Stream labels keep their names. Structured metadata is added in label
    # order, with one suffix on collision and no replacement of an occupied
    # suffixed name, matching Loki's LabelsBuilder.Add.
    base_labels =
      (record.resource || %{})
      |> maybe_put("service", record.service)
      |> maybe_put("service_name", record.service)
      |> maybe_put("level", record.severity_text)
      |> maybe_put("detected_level", record.severity_text)

    attributes =
      Enum.reduce([{"trace_id", record.trace_id}, {"span_id", record.span_id}], record.attributes || %{}, fn
        {_name, value}, attributes when value in [nil, ""] -> attributes
        {name, value}, attributes -> Map.put_new(attributes, name, value)
      end)

    {labels, metadata} =
      Enum.reduce(Enum.sort(attributes), {stringify_values(base_labels), %{}}, fn {name, value}, {labels, metadata} ->
        target = if Map.has_key?(base_labels, name), do: name <> "_extracted", else: name

        if target != name and Map.has_key?(labels, target) do
          {labels, metadata}
        else
          value = stringify(value)
          {Map.put(labels, target, value), Map.put(metadata, target, value)}
        end
      end)

    categories =
      if categorize_labels? do
        base_labels
        |> Map.new(fn {name, _} -> {name, :stream} end)
        |> Map.merge(
          Map.new(metadata, fn
            {name, _} when name in ["__error__", "__error_details__"] -> {name, :parsed}
            {name, _} -> {name, :structured_metadata}
          end)
        )
      end

    %__MODULE__{
      timestamp_ns: record.timestamp_ns,
      line: to_line(record.body),
      labels: labels,
      base_labels: base_labels,
      metadata_labels: metadata,
      label_categories: categories,
      error_labels: Map.take(metadata, ["__error__", "__error_details__"]),
      ordinary_error_labels:
        base_labels
        |> Map.take(["__error__", "__error_details__"])
        |> Map.new(fn {name, value} -> {name, {stringify(value), :stream}} end)
    }
  end

  # `labels` remains the rendered bag for output/template consumers. Only the
  # two reserved names need a shadow: Loki's ordinary Set/Get/Del are separate
  # from SetErr/ResetError. No second full label map is retained or copied.
  @error_names ["__error__", "__error_details__"]

  @doc false
  def initialize_errors(%{error_labels: nil} = entry) do
    # As with base-label provenance, manually constructed entries start with
    # ordinary stream labels. Only from_record metadata and set_error establish
    # authoritative errors; a same-named base label is not a SetErr call.
    ordinary =
      Map.new(Map.take(entry.labels, @error_names), fn {name, value} ->
        {name, {value, Map.get(entry.label_categories || %{}, name, :stream)}}
      end)

    %{entry | error_labels: %{}, ordinary_error_labels: ordinary}
  end

  def initialize_errors(entry), do: entry

  @doc false
  def error_value(entry, name), do: Map.get(entry.error_labels || %{}, name, "")

  @doc false
  def fetch_label(%{error_labels: nil} = entry, name) when name in @error_names,
    do: fetch_label(initialize_errors(entry), name)

  def fetch_label(entry, name) when name in @error_names do
    case Map.fetch(entry.ordinary_error_labels, name) do
      {:ok, {value, _category}} -> {:ok, value}
      :error -> :error
    end
  end

  def fetch_label(entry, name), do: Map.fetch(entry.labels, name)

  @doc false
  def label_value(entry, name) do
    case fetch_label(entry, name) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  @doc false
  def set_error(entry, error, details \\ nil) do
    entry = initialize_errors(entry)
    errors = %{"__error__" => error}
    errors = if details in [nil, ""], do: errors, else: Map.put(errors, "__error_details__", details)
    refresh_errors(%{entry | error_labels: errors})
  end

  @doc false
  def drop_label(entry, name) when name in @error_names do
    entry = initialize_errors(entry)
    refresh_errors(%{entry | error_labels: Map.delete(entry.error_labels, name)})
  end

  def drop_label(entry, name), do: delete_label(entry, name)

  @doc false
  def ordinary_labels(%{error_labels: errors} = entry) when is_nil(errors) or errors == %{}, do: entry.labels

  def ordinary_labels(entry) do
    Enum.reduce(@error_names, entry.labels, fn name, labels ->
      case fetch_label(entry, name) do
        {:ok, value} -> Map.put(labels, name, value)
        :error -> Map.delete(labels, name)
      end
    end)
  end

  @doc false
  def preserve_error_labels(entry, labels) do
    if error_value(entry, "__error__") == "" do
      labels
    else
      labels
      |> Map.drop(@error_names)
      |> Map.merge(Map.reject(entry.error_labels, fn {_name, value} -> value == "" end))
    end
  end

  defp refresh_errors(entry) do
    Enum.reduce(@error_names, entry, fn name, acc ->
      {value, category} =
        case error_value(acc, name) do
          "" -> Map.get(acc.ordinary_error_labels, name, {nil, nil})
          value -> {value, :parsed}
        end

      labels = if is_nil(value), do: Map.delete(acc.labels, name), else: Map.put(acc.labels, name, value)

      categories =
        case acc.label_categories do
          nil -> nil
          categories when is_nil(category) -> Map.delete(categories, name)
          categories -> Map.put(categories, name, category)
        end

      %{acc | labels: labels, label_categories: categories}
    end)
  end

  @doc false
  def extraction_name(entry, name) do
    if Map.has_key?(entry.base_labels, name) or Map.has_key?(entry.metadata_labels, name),
      do: name <> "_extracted",
      else: name
  end

  @doc false
  def extracted?(entry, name), do: Map.has_key?(entry.extracted_labels, name)

  @doc false
  def put_label(entry, name, value, category) when name in @error_names do
    entry = initialize_errors(entry)
    entry = %{entry | ordinary_error_labels: Map.put(entry.ordinary_error_labels, name, {value, category})}
    # Ordinary parser ownership still records an extraction, even when hidden
    # by the authoritative pipeline error.
    extracted = if category == :parsed, do: Map.put(entry.extracted_labels, name, true), else: entry.extracted_labels
    refresh_errors(%{entry | extracted_labels: extracted})
  end

  def put_label(entry, name, value, category) do
    categories = if entry.label_categories, do: Map.put(entry.label_categories, name, category)

    metadata =
      if category == :structured_metadata,
        do: Map.put(entry.metadata_labels, name, value),
        else: Map.delete(entry.metadata_labels, name)

    extracted = if category == :parsed, do: Map.put(entry.extracted_labels, name, true), else: entry.extracted_labels

    %{
      entry
      | labels: Map.put(entry.labels, name, value),
        label_categories: categories,
        metadata_labels: metadata,
        extracted_labels: extracted
    }
  end

  @doc false
  def delete_label(entry, name) when name in @error_names do
    entry = initialize_errors(entry)
    base = if entry.base_labels, do: Map.delete(entry.base_labels, name)

    refresh_errors(%{
      entry
      | ordinary_error_labels: Map.delete(entry.ordinary_error_labels, name),
        base_labels: base,
        metadata_labels: Map.delete(entry.metadata_labels, name)
    })
  end

  def delete_label(entry, name) do
    categories = if entry.label_categories, do: Map.delete(entry.label_categories, name)
    base = if entry.base_labels, do: Map.delete(entry.base_labels, name)

    %{
      entry
      | labels: Map.delete(entry.labels, name),
        label_categories: categories,
        base_labels: base,
        metadata_labels: Map.delete(entry.metadata_labels, name)
    }
  end

  @doc false
  def keep_labels(entry, labels) do
    # Keep never deletes either reserved name, including hidden ordinary values.
    labels = Map.merge(labels, Map.take(entry.labels, @error_names))
    names = Map.keys(labels)
    categories = if entry.label_categories, do: Map.take(entry.label_categories, names)
    base = if entry.base_labels, do: Map.take(entry.base_labels, names)

    %{
      entry
      | labels: labels,
        label_categories: categories,
        base_labels: base,
        metadata_labels: Map.take(entry.metadata_labels, names)
    }
  end

  @doc false
  # Called only on selected entries, after the unchanged global top-k. Empty
  # per-entry categories still encode as {}, never as an omitted third value.
  def categorized_labels(%__MODULE__{label_categories: categories, labels: labels}) when is_map(categories) do
    Enum.reduce(labels, {%{}, %{}}, fn {name, value}, {stream, entry} ->
      case Map.fetch!(categories, name) do
        :stream -> {Map.put(stream, name, value), entry}
        :structured_metadata -> {stream, put_category(entry, "structuredMetadata", name, value)}
        :parsed -> {stream, put_category(entry, "parsed", name, value)}
      end
    end)
  end

  defp put_category(categories, category, name, value),
    do: Map.update(categories, category, %{name => value}, &Map.put(&1, name, value))

  # LogQL matchers compare against strings. Non-string label values coming
  # from OTLP attributes (numbers, booleans) get stringified once at entry
  # time so every downstream matcher can rely on the invariant.
  defp stringify_values(map) do
    Map.new(map, fn {k, v} -> {k, stringify(v)} end)
  end

  defp stringify(v) when is_binary(v), do: v
  defp stringify(v) when is_integer(v), do: Integer.to_string(v)
  defp stringify(v) when is_float(v), do: Float.to_string(v)
  defp stringify(true), do: "true"
  defp stringify(false), do: "false"
  defp stringify(nil), do: ""
  defp stringify(v), do: inspect(v)

  defp maybe_put(map, _key, nil), do: map

  defp maybe_put(map, key, value) do
    if Map.has_key?(map, key), do: map, else: Map.put(map, key, value)
  end

  defp to_line(nil), do: ""
  defp to_line(body) when is_binary(body), do: body
  defp to_line(body), do: Pulse.JSON.encode!(body)
end
