defmodule Pulse.Storage.S3.Manifest do
  @moduledoc """
  Per-tenant, per-signal manifest data model.

  A manifest lists the segments that currently exist for one
  `(tenant, signal)` — each with its full time bounds and a small
  summary. Query time uses those bounds to prune segments that cannot
  match, so the vast majority of segment reads never happen.

  The wire form is JSON per `docs/architecture.md`. Every field name is
  short (`v`, `s`, `k`, `mn`, `mx`, `r`, `b`) so a manifest with thousands
  of segments stays small on the wire, and every decode is a single
  linear pass over the received bytes.

  ## In-memory invariants

    * `segments` is kept sorted by `max_ts` **descending**. The query
      pruner walks it in order and stops as soon as the accumulated
      k-th largest timestamp beats every remaining segment's `max_ts`.
      Pre-sorting on load means each query pays O(n) filter, not
      O(n log n) sort.
    * A segment's `key` on the wire is the tail after the tenant/signal
      prefix (e.g. `00000...20-00000...30-idem-<hash>.parquet`), never
      the full path. Two reasons: it halves manifest bytes, and it makes
      it impossible for a hand-crafted manifest to reference an object
      outside its own tenant prefix.

  ## Compaction

    * `merge/2` takes an existing manifest and a batch of newly-written
      segments and returns a new manifest with them merged in. The merge
      is a single pass through both lists (both sorted by `max_ts` desc)
      producing a sorted output — O(n) rather than O(n log n).
  """

  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Manifest.Retirement
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.PagedManifest

  @schema_version 1
  @name_dictionary_bytes 65_536
  # Encode-cache entry holding the log service-name and error-label-set
  # dictionaries, each {entry => id string, entries in reverse ID order, bytes}.
  @log_dictionaries :log_dictionaries
  @empty_logs {{%{}, [], 2}, {%{}, [], 2}}

  # `tenant` and `signal` are not serialized — they are derivable from
  # the manifest object's own key. Keeping them off the wire keeps the
  # payload smaller and forecloses a class of tenant-mixing bugs.
  defstruct version: @schema_version, segments: [], retired: %{}, cleanup_cursor: nil, paging: nil

  @type t :: %__MODULE__{
          version: non_neg_integer(),
          segments: [Segment.t()],
          retired: %{String.t() => Retirement.t()},
          cleanup_cursor: String.t() | nil,
          paging: map() | nil
        }

  @doc "Path of the manifest object for one `(tenant, signal)`."
  @spec manifest_key(String.t(), String.t()) :: String.t()
  def manifest_key(tenant, signal \\ "logs") when is_binary(tenant) and is_binary(signal) do
    "tenants/#{tenant}/v4/signal=#{signal}/manifest.json"
  end

  @doc "An empty manifest — the shape a first-time `put_if_none_match` uploads."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Encode a manifest to iodata for transport.

  Callers collapse to a binary with `IO.iodata_to_binary/1` only at the
  NIF boundary — the intermediate steps stay as iodata to avoid extra
  per-segment binary allocations.
  """
  @spec encode(t()) :: iodata()
  def encode(%__MODULE__{} = manifest), do: manifest |> encode_with(nil) |> elem(0)

  @doc """
  Encode like `encode/1`, reusing each unchanged segment's JSON from `cache`.

  A flat manifest is rewritten on every publication, so re-encoding every
  segment (including base64 of trace blooms) makes each flush proportional to
  the whole history. The cache maps a segment key to the exact segment term and
  its encoded object; an entry is reused only when the segment is identical.
  Dictionary IDs are still assigned per call in segment order, so the result is
  the same document `encode/1` produces. Returns the cache for the next call,
  holding only current segments.
  """
  @spec encode(t(), map()) :: {iodata(), map()}
  def encode(%__MODULE__{} = manifest, cache) when is_map(cache), do: encode_with(manifest, cache)

  defp encode_with(
         %__MODULE__{version: version, segments: segments, retired: retired, cleanup_cursor: cursor} = manifest,
         cache
       ) do
    {wire_segments, names, labels, services, log_labels, cache} = encode_segments(segments, cache)

    wire = %{
      "v" => version,
      "retired" => Map.new(retired, fn {key, retirement} -> {key, Retirement.to_wire(retirement)} end),
      "cleanup_cursor" => cursor
    }

    wire = if version in [3, 4], do: Map.put(wire, "p", manifest.paging), else: wire
    wire = if names == [], do: wire, else: Map.put(wire, "names", names)
    wire = if labels == [], do: wire, else: Map.put(wire, "labels", labels)
    wire = if services == [], do: wire, else: Map.put(wire, "services", services)
    wire = if log_labels == [], do: wire, else: Map.put(wire, "log_labels", log_labels)
    # `wire` always holds "v", so its object has at least one member to follow.
    rest = wire |> Pulse.JSON.encode_to_iodata!() |> IO.iodata_to_binary()
    json = ["{\"s\":[", Enum.intersperse(wire_segments, ?,), "],", binary_part(rest, 1, byte_size(rest) - 1)]

    if version in [3, 4] do
      # Verify exact payload bytes, independent of OTP term encoding or JSON
      # map iteration order across reader/writer upgrades.
      {["{\"root_sha\":\"", root_digest(json), "\",\"payload\":", json, "}"], cache}
    else
      {json, cache}
    end
  end

  @doc """
  Decode a manifest from its wire form.

  Guarantees the returned struct maintains the sorted invariant even
  if the wire form was out of order (belt and braces — a well-behaved
  writer produces sorted output, and a hostile one still gets sorted
  before we trust the invariant).
  """
  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(binary) when is_binary(binary) do
    with {:ok, payload, protected?} <- unwrap_root(binary),
         {:ok, %{"v" => version, "s" => segments} = wire} <- safe_decode(payload),
         :ok <- validate_version(version),
         :ok <- validate_fields(version, wire),
         {:ok, parsed} <-
           decode_segments(
             segments,
             name_dictionary(wire["names"]),
             name_dictionary(wire["labels"]),
             {name_dictionary(wire["services"]), name_dictionary(wire["log_labels"])}
           ),
         {:ok, retired} <- decode_retired(Map.get(wire, "retired", %{})),
         {:ok, cursor} <- decode_cursor(Map.get(wire, "cleanup_cursor")),
         :ok <- validate_paging(version, wire["p"]),
         :ok <- validate_root_bounds(version, parsed, byte_size(binary)),
         :ok <- validate_root_digest(version, protected?) do
      {:ok,
       %__MODULE__{
         version: version,
         segments: sort_by_max_ts_desc(parsed),
         retired: retired,
         cleanup_cursor: cursor,
         paging: wire["p"]
       }}
    else
      {:ok, _malformed} -> {:error, :invalid_manifest}
      {:error, _} = err -> err
    end
  end

  # Tombstones remain after deletion: a delayed idempotent ingest retry must
  # never reintroduce records that already live in a replacement segment.
  defp validate_version(version) when version in [1, 2, 3, 4], do: :ok
  defp validate_version(_), do: {:error, :unsupported_manifest_version}

  defp validate_paging(3, paging), do: PagedManifest.validate(paging)
  defp validate_paging(4, paging), do: JournalManifest.validate(paging)
  defp validate_paging(_, nil), do: :ok
  defp validate_paging(_, _), do: {:error, :invalid_manifest}

  defp validate_fields(1, _wire), do: :ok
  defp validate_fields(2, %{"retired" => _}), do: :ok
  defp validate_fields(3, %{"retired" => retired, "p" => _}) when is_map(retired) and map_size(retired) == 0, do: :ok
  defp validate_fields(4, %{"retired" => retired, "p" => _} = wire) when is_map(retired), do: no_cursor(wire)
  defp validate_fields(_, _wire), do: {:error, :invalid_manifest}

  defp root_digest(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp unwrap_root(<<"{\"root_sha\":\"", sha::binary-size(64), "\",\"payload\":", rest::binary>>) do
    if byte_size(rest) > 0 and :binary.last(rest) == ?} do
      payload = binary_part(rest, 0, byte_size(rest) - 1)
      if root_digest(payload) == sha, do: {:ok, payload, true}, else: {:error, :invalid_manifest}
    else
      {:error, :invalid_manifest}
    end
  end

  defp unwrap_root(bytes), do: {:ok, bytes, false}
  defp validate_root_digest(version, true) when version in [3, 4], do: :ok
  defp validate_root_digest(version, _) when version in [3, 4], do: {:error, :invalid_manifest}
  defp validate_root_digest(_, false), do: :ok
  defp validate_root_digest(_, _), do: {:error, :invalid_manifest}

  defp validate_root_bounds(3, segments, bytes) do
    tail_bytes = segments |> Enum.map(&Segment.to_wire/1) |> Pulse.JSON.encode_to_iodata!() |> IO.iodata_length()

    if bytes <= 524_288 and length(segments) <= 256 and tail_bytes <= 65_536,
      do: :ok,
      else: {:error, :retention_capacity}
  end

  defp validate_root_bounds(4, segments, bytes) do
    if bytes <= JournalManifest.root_limit() and length(segments) <= JournalManifest.root_entries(),
      do: :ok,
      else: {:error, :manifest_capacity}
  end

  defp validate_root_bounds(_, _, _), do: :ok

  # Format 4 tracks cleanup per page, not with a flat key cursor.
  defp no_cursor(%{"cleanup_cursor" => cursor}) when not is_nil(cursor), do: {:error, :invalid_manifest}
  defp no_cursor(_wire), do: :ok

  @doc "Whether a root references no segment or retirement at all, including through pages."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{segments: [], retired: retired, version: 4, paging: %{"refs" => refs}}),
    do: map_size(retired) == 0 and refs == []

  def empty?(%__MODULE__{segments: segments, retired: retired, version: version}) when version in [1, 2, 3],
    do: segments == [] and map_size(retired) == 0

  def empty?(%__MODULE__{}), do: false

  defp decode_cursor(cursor) when is_nil(cursor) or is_binary(cursor), do: {:ok, cursor}
  defp decode_cursor(_), do: {:error, :invalid_manifest}

  defp decode_retired(retired) when is_map(retired) do
    Enum.reduce_while(retired, {:ok, %{}}, fn {key, wire}, {:ok, acc} ->
      case Retirement.from_wire(wire) do
        {:ok, retirement} when is_binary(key) -> {:cont, {:ok, Map.put(acc, key, retirement)}}
        _ -> {:halt, {:error, :invalid_manifest}}
      end
    end)
  end

  defp decode_retired(_), do: {:error, :invalid_manifest}

  @doc "Mark successful deletions only if no ingest retry changed their revision."
  def mark_deleted(manifest, deleted, cursor) do
    retired =
      Enum.reduce(deleted, manifest.retired, fn {key, observed}, acc ->
        if Map.get(acc, key) == observed, do: Map.put(acc, key, %{observed | deleted?: true}), else: acc
      end)

    %{manifest | retired: retired, cleanup_cursor: cursor}
  end

  @doc "Replace active sources atomically, retaining durable deletion deadlines."
  @spec replace(t(), [String.t()], Segment.t(), non_neg_integer()) :: {:ok, t()} | {:error, term()}
  def replace(manifest, source_keys, replacement, delete_after) do
    if MapSet.size(MapSet.new(source_keys)) >= 2,
      do: replace_all(manifest, source_keys, [replacement], delete_after),
      else: {:error, :compaction_conflict}
  end

  @doc """
  Retire every active source and add `replacements` in one transition, as
  hour finalization does. Fails with `:compaction_conflict` unless every source
  is still active and no replacement is known.
  """
  def replace_all(manifest, source_keys, replacements, delete_after) do
    sources = MapSet.new(source_keys)
    active = MapSet.new(manifest.segments, & &1.key)

    if MapSet.size(sources) >= 1 and MapSet.subset?(sources, active) and
         Enum.all?(replacements, &(not MapSet.member?(active, &1.key) and not Map.has_key?(manifest.retired, &1.key))) do
      retired = Enum.reduce(source_keys, manifest.retired, &Map.put(&2, &1, Retirement.new(delete_after)))
      remaining = Enum.reject(manifest.segments, &MapSet.member?(sources, &1.key))

      {:ok, merge(%{manifest | version: 2, segments: remaining, retired: retired}, replacements)}
    else
      {:error, :compaction_conflict}
    end
  end

  # Manifests outlive the GET that read them (cache, owners, retries), so
  # their strings must not stay sub-binaries of the response body.
  defp safe_decode(binary) do
    {:ok, binary |> Pulse.JSON.decode!() |> Pulse.JSON.detach()}
  rescue
    e -> {:error, {:decode_failed, e}}
  end

  defp decode_segments(list, dictionary, labels, logs) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn wire, {:ok, acc} ->
      wire = wire |> expand_names(dictionary) |> expand_labels(labels) |> expand_log_summaries(logs)

      case Segment.from_wire(wire) do
        {:ok, segment} -> {:cont, {:ok, [segment | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp decode_segments(_, _, _, _), do: {:error, :invalid_manifest}

  # Exact name sets repeat across ingest batches. One dictionary entry per set
  # keeps that repetition off the hot manifest, with a hard byte budget for
  # distinct sets. Omitted sets remain unknown, so budget exhaustion is safe.
  #
  # Log segments reference each promoted service name ("si") and their error
  # label set ("ei") through two more dictionaries, which cuts a staging-shaped
  # log entry by about 30%. Older readers ignore these fields and treat the
  # summaries as unknown, which only disables pruning. These dictionaries live
  # in the encode cache, so their IDs stay stable across flushes and a cached
  # fragment keeps its own. They restart, re-encoding every fragment, only when
  # a new entry exceeds an inherited dictionary's budget.
  defp encode_segments(segments, cache) do
    {logs, cache} = if cache, do: Map.pop(cache, @log_dictionaries, @empty_logs), else: {@empty_logs, nil}

    state = %{
      ids: %{},
      names: [],
      bytes: 2,
      segments: [],
      label_ids: %{},
      labels: [],
      label_bytes: 2,
      logs: logs,
      inherited?: logs != @empty_logs,
      cache: cache
    }

    case Enum.reduce_while(segments, state, &encode_segment/2) do
      :restart ->
        encode_segments(segments, %{})

      state ->
        cache = if state.cache, do: state.cache |> prune_cache(segments) |> Map.put(@log_dictionaries, state.logs)
        {services, error_labels} = state.logs

        {Enum.reverse(state.segments), Enum.reverse(state.names), Enum.reverse(state.labels),
         dictionary_entries(services), dictionary_entries(error_labels), cache}
    end
  end

  defp dictionary_entries({ids, _entries, _bytes}) when map_size(ids) == 0, do: []
  defp dictionary_entries({_ids, entries, _bytes}), do: Enum.reverse(entries)

  defp encode_segment(segment, state) do
    case segment_fragment(segment, state) do
      :restart ->
        {:halt, :restart}

      {fragment, state} ->
        {name_id, state} = dictionary_id(segment.metric_names, state)
        {label_id, state} = label_dictionary_id(segment.metric_labels, state)
        {:cont, %{state | segments: [with_dictionary_ids(fragment, name_id, label_id) | state.segments]}}
    end
  end

  # The fragment is the segment's JSON object with its log summary IDs but
  # without its metric name/label sets, which per-call dictionaries replace.
  defp segment_fragment(segment, %{cache: nil} = state), do: encode_fragment(segment, state)

  defp segment_fragment(%{key: key} = segment, %{cache: cache} = state) do
    case cache do
      %{^key => {^segment, fragment}} ->
        {fragment, state}

      _ ->
        with {fragment, state} <- encode_fragment(segment, state),
             do: {fragment, %{state | cache: Map.put(state.cache, key, {segment, fragment})}}
    end
  end

  # A fresh binary, so a cached fragment never pins a larger payload.
  defp encode_fragment(segment, state) do
    {services, error_labels} = state.logs

    with {services_member, services} <- log_member(segment.log_services, services, "si", "ls", state.inherited?),
         {labels_member, error_labels} <- log_member(segment.log_labels, error_labels, "ei", "el", state.inherited?) do
      wire = segment |> Segment.to_wire() |> Map.drop(["n", "l", "ls", "el"]) |> Pulse.JSON.encode_to_iodata!()
      wire = IO.iodata_to_binary(wire)

      fragment =
        if services_member == [] and labels_member == [],
          do: wire,
          else: IO.iodata_to_binary([binary_part(wire, 0, byte_size(wire) - 1), services_member, labels_member, ?}])

      {fragment, %{state | logs: {services, error_labels}}}
    end
  end

  # Services are listed by name ID, error label sets by set ID. An entry
  # beyond the budget of a fresh dictionary keeps the summary inline; an
  # inherited one may be full of entries no longer listed, so start over.
  defp log_member(nil, dictionary, _field, _inline, _inherited?), do: {[], dictionary}

  defp log_member(names, dictionary, "si", inline, inherited?) do
    {ids, dictionary} = Enum.map_reduce(names, dictionary, &persistent_id/2)

    if Enum.all?(ids, &is_binary/1),
      do: {[",\"si\":[", Enum.intersperse(ids, ?,), ?]], dictionary},
      else: overflow(names, dictionary, inline, inherited?)
  end

  defp log_member(labels, dictionary, field, inline, inherited?) do
    case persistent_id(labels, dictionary) do
      {nil, dictionary} -> overflow(labels, dictionary, inline, inherited?)
      {id, dictionary} -> {[",\"", field, "\":", id], dictionary}
    end
  end

  defp overflow(_value, _dictionary, _inline, true), do: :restart

  defp overflow(value, dictionary, inline, false),
    do: {[",\"", inline, "\":", Pulse.JSON.encode_to_iodata!(value)], dictionary}

  defp persistent_id(value, {ids, entries, bytes} = dictionary) do
    case ids do
      %{^value => id} ->
        {id, dictionary}

      _ ->
        size = value |> Pulse.JSON.encode_to_iodata!() |> IO.iodata_length()

        if bytes + size + 1 <= @name_dictionary_bytes do
          id = Integer.to_string(map_size(ids))
          {id, {Map.put(ids, value, id), [value | entries], bytes + size + 1}}
        else
          {nil, dictionary}
        end
    end
  end

  defp with_dictionary_ids(fragment, nil, nil), do: fragment

  defp with_dictionary_ids(fragment, name_id, label_id) do
    [
      binary_part(fragment, 0, byte_size(fragment) - 1),
      dictionary_member("ni", name_id),
      dictionary_member("li", label_id),
      ?}
    ]
  end

  defp dictionary_member(_, nil), do: []
  defp dictionary_member(field, id), do: [",\"", field, "\":", Integer.to_string(id)]

  # Appends only add keys; drop entries for removed segments when there are any.
  defp prune_cache(cache, segments) do
    if map_size(cache) > length(segments), do: Map.take(cache, Enum.map(segments, & &1.key)), else: cache
  end

  defp dictionary_id(nil, state), do: {nil, state}

  defp dictionary_id(names, state) do
    case Map.fetch(state.ids, names) do
      {:ok, id} -> {id, state}
      :error -> add_name_set(names, state)
    end
  end

  defp add_name_set(names, state) do
    bytes = names |> Pulse.JSON.encode_to_iodata!() |> IO.iodata_length()

    if state.bytes + bytes + 1 <= @name_dictionary_bytes do
      id = map_size(state.ids)
      {id, %{state | ids: Map.put(state.ids, names, id), names: [names | state.names], bytes: state.bytes + bytes + 1}}
    else
      {nil, state}
    end
  end

  defp label_dictionary_id(nil, state), do: {nil, state}

  defp label_dictionary_id(labels, state) do
    case Map.fetch(state.label_ids, labels) do
      {:ok, id} ->
        {id, state}

      :error ->
        bytes = IO.iodata_length(Pulse.JSON.encode_to_iodata!(labels))

        if state.label_bytes + bytes + 1 <= @name_dictionary_bytes do
          id = map_size(state.label_ids)

          {id,
           %{
             state
             | label_ids: Map.put(state.label_ids, labels, id),
               labels: [labels | state.labels],
               label_bytes: state.label_bytes + bytes + 1
           }}
        else
          {nil, state}
        end
    end
  end

  defp expand_labels(%{"li" => id} = wire, dictionary) when is_integer(id) and id >= 0 and id < tuple_size(dictionary),
    do: Map.put(wire, "l", elem(dictionary, id))

  defp expand_labels(%{"li" => _} = wire, _), do: Map.put(wire, "l", nil)
  defp expand_labels(wire, _), do: wire

  # Unknown or out-of-range IDs leave a summary unknown, never wrong.
  defp expand_log_summaries(wire, {services, labels}),
    do: wire |> expand_services(services) |> expand_error_labels(labels)

  defp expand_services(%{"si" => ids} = wire, services) when is_list(ids) do
    names =
      Enum.map(ids, fn
        id when is_integer(id) and id >= 0 and id < tuple_size(services) -> elem(services, id)
        _ -> nil
      end)

    Map.put(wire, "ls", if(Enum.all?(names, &is_binary/1), do: names))
  end

  defp expand_services(%{"si" => _} = wire, _services), do: Map.put(wire, "ls", nil)
  defp expand_services(wire, _services), do: wire

  defp expand_error_labels(wire, labels) do
    case wire do
      %{"ei" => id} when is_integer(id) and id >= 0 and id < tuple_size(labels) -> Map.put(wire, "el", elem(labels, id))
      %{"ei" => _} -> Map.put(wire, "el", nil)
      _ -> wire
    end
  end

  defp name_dictionary(names) when is_list(names), do: List.to_tuple(names)
  defp name_dictionary(_), do: {}

  defp expand_names(%{"ni" => id} = wire, dictionary) when is_integer(id) and id >= 0 and id < tuple_size(dictionary),
    do: Map.put(wire, "n", elem(dictionary, id))

  defp expand_names(%{"ni" => _} = wire, _), do: Map.put(wire, "n", nil)
  defp expand_names(wire, _), do: wire

  @doc """
  Merge a batch of newly-written segments into an existing manifest.

  Both inputs are sorted by `max_ts` desc; the output preserves that
  invariant with an O(n) merge. Duplicate keys (a retry that already
  landed in the manifest) collapse to a single entry, preferring the
  incoming segment — its bounds and row_count are what the caller has
  in hand, and any drift from the previous entry would be silent
  otherwise.
  """
  @spec merge(t(), [Segment.t()]) :: t()
  def merge(%__MODULE__{} = manifest, []), do: manifest

  def merge(%__MODULE__{segments: existing} = manifest, new_segments) when is_list(new_segments) do
    # Dedup the incoming batch by key BEFORE the merge. Same-key
    # duplicates arise on the retry-idempotency path: two `register_segments`
    # calls carrying the same idempotency key produce two `%Segment{}`
    # values with identical S3 keys. Without this dedup they would BOTH
    # land in the merged manifest — one S3 object referenced twice — so
    # a later `query/2` would fetch that object twice and return each of
    # its records twice. `Enum.uniq_by/2` keeps the first occurrence,
    # which is fine here because the duplicates are byte-identical.
    retired = Enum.reduce(Enum.uniq_by(new_segments, & &1.key), manifest.retired, &retry_retired/2)
    deduped = new_segments |> Enum.reject(&Map.has_key?(manifest.retired, &1.key)) |> Enum.uniq_by(& &1.key)
    new_sorted = sort_by_max_ts_desc(deduped)
    merged = merge_sorted(new_sorted, existing, [], MapSet.new(Enum.map(new_sorted, & &1.key)))
    # Complete hash sets are only a paged-leaf construction aid. Flat point
    # lookups use adaptive/canonical blooms; don't retain/rewrite unused hashes
    # (or grow unbounded flat roots with attribute value sets) indefinitely.
    # Migration safely treats these absent sets as unknown.
    merged = if manifest.version < 3, do: Enum.map(merged, &thin_flat_trace_summary/1), else: merged
    %{manifest | segments: merged, retired: retired}
  end

  # Return already-thin segments unchanged, so they stay identical terms for the
  # owner's encode cache instead of being rebuilt on every merge.
  defp thin_flat_trace_summary(%{trace_summary: nil} = segment), do: segment
  defp thin_flat_trace_summary(%{trace_summary: %{lookup_hashes: nil, attributes: nil}} = segment), do: segment

  defp thin_flat_trace_summary(segment),
    do: %{segment | trace_summary: %{segment.trace_summary | lookup_hashes: nil, attributes: nil}}

  defp retry_retired(segment, retired) do
    case Map.fetch(retired, segment.key) do
      {:ok, retirement} -> Map.put(retired, segment.key, Retirement.retried(retirement))
      :error -> retired
    end
  end

  # `new` overrides `existing` on key collision — MapSet holds the keys
  # in `new`, so any element in `existing` with a matching key is skipped
  # rather than appended a second time.
  defp merge_sorted([], rest, acc, new_keys) do
    remaining = Enum.reject(rest, &MapSet.member?(new_keys, &1.key))
    Enum.reverse(acc, remaining)
  end

  defp merge_sorted(new, [], acc, _new_keys) do
    Enum.reverse(acc, new)
  end

  defp merge_sorted([n | rest_n] = new, [e | rest_e], acc, new_keys) do
    cond do
      MapSet.member?(new_keys, e.key) ->
        # `e` is superseded by the corresponding entry in `new`. Drop it
        # and keep merging.
        merge_sorted(new, rest_e, acc, new_keys)

      n.max_ts >= e.max_ts ->
        merge_sorted(rest_n, [e | rest_e], [n | acc], new_keys)

      true ->
        merge_sorted(new, rest_e, [e | acc], new_keys)
    end
  end

  @doc """
  Prune segments to those overlapping `[start_ts, end_ts]`.

  A nil bound is unbounded on that side. Segments with `nil` min/max
  (never produced by this codebase but possible in a hand-crafted or
  migrated manifest) are kept — the safe default.
  """
  @spec prune_by_time(t(), non_neg_integer() | nil, non_neg_integer() | nil) :: [Segment.t()]
  def prune_by_time(%__MODULE__{segments: segments}, nil, nil), do: segments

  def prune_by_time(%__MODULE__{segments: segments}, start_ts, end_ts) do
    Enum.filter(segments, &Segment.intersects?(&1, start_ts, end_ts))
  end

  defp sort_by_max_ts_desc(segments) do
    Enum.sort_by(segments, &segment_max_ts_for_sort/1, :desc)
  end

  # nil floats to the head — the safe default. Elixir's term order already
  # puts atoms greater than integers so a bare `Enum.sort_by(&(&1.max_ts))`
  # would do the same, but pinning it in a helper keeps the ordering
  # invariant explicit at the point it matters.
  defp segment_max_ts_for_sort(%{max_ts: nil}), do: :infinity
  defp segment_max_ts_for_sort(%{max_ts: ts}), do: ts
end
