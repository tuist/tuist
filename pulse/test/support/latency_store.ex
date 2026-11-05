defmodule Pulse.Test.LatencyStore do
  @moduledoc false
  # S3-compatible object store for load tests: conditional PUT/GET, suffix
  # ranges, DELETE and ListObjectsV2, with per-request latency drawn from
  # configured ranges. Metadata lives in a public ETS table, bodies in files
  # under `:dir`, so the store's own memory stays small while a test writes
  # gigabytes. Counts every request by S3 billing class, purpose and status.
  @behaviour Plug

  import Plug.Conn

  @doc """
  Create the tables a store needs; pass the result as the plug's options.
  With `restore: true`, objects saved by `save/1` in `:dir` are live again.
  """
  def new(opts) do
    dir = Keyword.fetch!(opts, :dir)
    File.mkdir_p!(dir)

    objects =
      if Keyword.get(opts, :restore, false) do
        {:ok, table} = :ets.file2tab(String.to_charlist(index_path(dir)))
        table
      else
        :ets.new(:latency_store_objects, [:public, :ordered_set, read_concurrency: true])
      end

    store = %{
      objects: objects,
      stats: :ets.new(:latency_store_stats, [:public, :set, write_concurrency: true]),
      lock: :ets.new(:latency_store_locks, [:public, :set]),
      latency: :ets.new(:latency_store_latency, [:public, :set, read_concurrency: true]),
      dir: dir
    }

    set_latency(store, opts)
    store
  end

  @doc "Write the object index next to the bodies, so `new(dir: dir, restore: true)` reopens the store."
  def save(store), do: :ok = :ets.tab2file(store.objects, String.to_charlist(index_path(store.dir)))

  @doc "Whether `dir` holds a saved store."
  def saved?(dir), do: File.exists?(index_path(dir))

  defp index_path(dir), do: Path.join(dir, "index.ets")

  @doc "Change request latencies (`:get_ms`, `:put_ms`, `:list_ms`, `:delete_ms` ranges) of a running store."
  def set_latency(store, opts) do
    defaults = [get_ms: {140, 190}, put_ms: {220, 350}, list_ms: {140, 190}, delete_ms: {100, 150}]
    for {name, default} <- defaults, do: :ets.insert(store.latency, {name, Keyword.get(opts, name, default)})
    :ok
  end

  @doc "Counters as `%{{class, purpose, method, status} => {count, bytes}}`; purposes name their signal (`segment:traces`)."
  def stats(store) do
    for {key, count, bytes} when is_tuple(key) <- :ets.tab2list(store.stats), into: %{}, do: {key, {count, bytes}}
  end

  @doc "Live objects and bytes by purpose and signal (`segment:logs`), excluding deleted and overwritten versions."
  def inventory(store) do
    :ets.foldl(
      fn {key, _etag, size, _}, acc ->
        Map.update(acc, purpose(key) <> signal(key), {1, size}, fn {n, b} -> {n + 1, b + size} end)
      end,
      %{},
      store.objects
    )
  end

  @doc "Bytes removed by DELETE and replaced by overwriting PUTs, which a soft-delete window keeps billable."
  def superseded(store) do
    case :ets.lookup(store.stats, :superseded) do
      [{:superseded, deleted, overwritten}] -> %{deleted: deleted, overwritten: overwritten}
      [] -> %{deleted: 0, overwritten: 0}
    end
  end

  def init(opts), do: opts

  def call(conn, store) do
    conn = fetch_query_params(conn)
    key = conn.request_path |> URI.decode() |> String.replace_prefix("/", "") |> strip_bucket()
    {body, conn} = read_full_body(conn, [])
    list? = conn.method == "GET" and Map.has_key?(conn.query_params, "list-type")
    {low, high} = latency(store, conn.method, list?)
    if high > 0, do: Process.sleep(low + :rand.uniform(high - low + 1) - 1)

    {status, headers, response} =
      if list? do
        {200, [], list(store, conn)}
      else
        request(store, conn.method, key, body, conn)
      end

    count(store, conn.method, list?, key, status, byte_size(body) + response_size(response))
    conn = Enum.reduce(headers, conn, fn {name, value}, conn -> put_resp_header(conn, name, value) end)
    send_resp(conn, status, response)
  end

  defp strip_bucket(path) do
    case String.split(path, "/", parts: 2) do
      [_bucket, key] -> key
      [_bucket] -> ""
    end
  end

  defp response_size(response) when is_binary(response), do: byte_size(response)
  defp response_size(response), do: IO.iodata_length(response)

  defp latency(store, "PUT", _), do: latency(store, :put_ms)
  defp latency(store, "DELETE", _), do: latency(store, :delete_ms)
  defp latency(store, "GET", true), do: latency(store, :list_ms)
  defp latency(store, _, _), do: latency(store, :get_ms)
  defp latency(store, name), do: :ets.lookup_element(store.latency, name, 2)

  # Tigris bills PUT/LIST as Class A and GET/HEAD as Class B; DELETE, 304 and
  # 412 responses are free.
  defp count(store, method, list?, key, status, bytes) do
    class =
      cond do
        method == "DELETE" or status in [304, 409, 412] -> "free"
        method == "PUT" or list? -> "A"
        true -> "B"
      end

    purpose = if list?, do: "list", else: detail(key) <> signal(key)
    slot = {class, purpose, method, status}
    :ets.update_counter(store.stats, slot, [{2, 1}, {3, bytes}], {slot, 0, 0})
  end

  defp signal(key) do
    case Regex.run(~r{/signal=(\w+)/}, key) do
      [_, signal] -> ":" <> signal
      _ -> ""
    end
  end

  @doc false
  def purpose(key) do
    cond do
      String.ends_with?(key, "/manifest.json") -> "manifest"
      String.ends_with?(key, ".parquet") -> "segment"
      String.ends_with?(key, ".json") -> "metadata_page"
      true -> "other"
    end
  end

  # Billing purpose refined by what wrote the object: ingest (`-rand-`),
  # keyed (`-idem-`), compaction, metric grouping/finalization and rollups,
  # and the journal page kinds of paged manifests.
  @doc false
  def detail(key) do
    base = Path.basename(key)

    tag =
      case purpose(key) do
        "segment" ->
          Enum.find(~w(rand idem compact group final edge rollup), "other", &String.contains?(base, "-#{&1}-"))

        "metadata_page" ->
          Enum.find(~w(leaf index gc), "other", &String.ends_with?(base, "-#{&1}.json"))

        _ ->
          nil
      end

    if tag, do: purpose(key) <> "/" <> tag, else: purpose(key)
  end

  defp read_full_body(conn, chunks) do
    case read_body(conn, length: 64_000_000) do
      {:more, chunk, conn} -> read_full_body(conn, [chunk | chunks])
      {:ok, chunk, conn} -> {IO.iodata_to_binary(Enum.reverse([chunk | chunks])), conn}
    end
  end

  defp path(store, key), do: Path.join(store.dir, Base.url_encode64(:crypto.hash(:sha256, key), padding: false))

  defp write(store, key, body, current) do
    etag = "\"#{System.unique_integer([:positive, :monotonic])}\""
    with [{_, _, size, _}] <- current, do: supersede(store, 0, size)
    File.write!(path(store, key), body)
    :ets.insert(store.objects, {key, etag, byte_size(body), System.os_time(:second)})
    {200, [{"etag", etag}], ""}
  end

  # Conditional writes are serialized per key with an ETS lock.
  defp request(store, "PUT", key, body, conn) do
    match = List.first(get_req_header(conn, "if-match"))
    none = List.first(get_req_header(conn, "if-none-match"))

    with_lock(store, key, fn ->
      current = :ets.lookup(store.objects, key)

      conflict? =
        (match != nil and not match?([{_, ^match, _, _}], current)) or (none == "*" and current != [])

      if conflict?, do: {412, [], ""}, else: write(store, key, body, current)
    end)
  end

  defp request(store, "GET", key, _body, conn) do
    none = List.first(get_req_header(conn, "if-none-match"))
    match = List.first(get_req_header(conn, "if-match"))
    range = List.first(get_req_header(conn, "range"))

    case :ets.lookup(store.objects, key) do
      [] ->
        {404, [], ""}

      [{_, etag, _, _}] when match != nil and match != etag ->
        {412, [{"etag", etag}], ""}

      [{_, etag, _, _}] when etag == none ->
        {304, [{"etag", etag}], ""}

      [{_, etag, _, _}] ->
        case File.read(path(store, key)) do
          {:ok, body} when is_binary(range) -> suffix(etag, body, range)
          {:ok, body} -> {200, [{"etag", etag}], body}
          # Deleted between lookup and read.
          {:error, _} -> {404, [], ""}
        end
    end
  end

  defp request(store, "DELETE", key, _body, _conn) do
    with_lock(store, key, fn ->
      with [{_, _, size, _}] <- :ets.lookup(store.objects, key), do: supersede(store, size, 0)
      :ets.delete(store.objects, key)
      File.rm(path(store, key))
      {204, [], ""}
    end)
  end

  defp request(_store, "HEAD", _key, _body, _conn), do: {405, [], ""}

  defp supersede(store, deleted, overwritten),
    do: :ets.update_counter(store.stats, :superseded, [{2, deleted}, {3, overwritten}], {:superseded, 0, 0})

  defp with_lock(store, key, fun) do
    if :ets.insert_new(store.lock, {key}) do
      try do
        fun.()
      after
        :ets.delete(store.lock, key)
      end
    else
      Process.sleep(1)
      with_lock(store, key, fun)
    end
  end

  defp suffix(etag, body, range) do
    case Integer.parse(String.replace_prefix(range, "bytes=-", "")) do
      {suffix, ""} when suffix > 0 ->
        first = max(0, byte_size(body) - suffix)
        bytes = binary_part(body, first, byte_size(body) - first)
        {206, [{"etag", etag}, {"content-range", "bytes #{first}-#{byte_size(body) - 1}/#{byte_size(body)}"}], bytes}

      _ ->
        {416, [{"etag", etag}], ""}
    end
  end

  defp list(store, conn) do
    prefix = Map.get(conn.query_params, "prefix", "")

    start =
      case Map.get(conn.query_params, "continuation-token") do
        nil -> Map.get(conn.query_params, "start-after", "")
        token -> Base.url_decode64!(token, padding: false)
      end

    limit = conn.query_params |> Map.get("max-keys", "1000") |> String.to_integer() |> min(1000)
    delimiter = Map.get(conn.query_params, "delimiter")
    {entries, last, truncated?} = scan(store, prefix, start, delimiter, limit)

    token =
      if truncated?,
        do: "<NextContinuationToken>#{Base.url_encode64(last, padding: false)}</NextContinuationToken>",
        else: ""

    [
      ~s(<?xml version="1.0" encoding="UTF-8"?><ListBucketResult><Name>pulse</Name><Prefix>),
      escape(prefix),
      "</Prefix><KeyCount>#{length(entries)}</KeyCount><MaxKeys>#{limit}</MaxKeys><IsTruncated>#{truncated?}</IsTruncated>",
      token,
      entries,
      "</ListBucketResult>"
    ]
  end

  # Walks keys after `start` in order; with a delimiter, each common prefix
  # appears once and the walk jumps past its subtree.
  defp scan(store, prefix, start, delimiter, limit) do
    first = if start > prefix, do: :ets.next(store.objects, start), else: first_at(store, prefix)
    walk(store, first, prefix, delimiter, limit, [], start)
  end

  defp first_at(store, prefix) do
    case :ets.lookup(store.objects, prefix) do
      [_] -> prefix
      [] -> :ets.next(store.objects, prefix)
    end
  end

  defp walk(_store, _key, _prefix, _delimiter, 0, acc, last), do: {Enum.reverse(acc), last, true}
  defp walk(_store, :"$end_of_table", _prefix, _delimiter, _left, acc, last), do: {Enum.reverse(acc), last, false}

  defp walk(store, key, prefix, delimiter, left, acc, last) do
    if String.starts_with?(key, prefix) do
      rest = binary_part(key, byte_size(prefix), byte_size(key) - byte_size(prefix))

      case delimiter && :binary.match(rest, delimiter) do
        {at, _} ->
          common = prefix <> binary_part(rest, 0, at + 1)
          entry = "<CommonPrefixes><Prefix>#{escape(common)}</Prefix></CommonPrefixes>"
          # Skip the whole subtree: the next key not starting with `common`.
          next = :ets.next(store.objects, common <> <<255>>)
          walk(store, next, prefix, delimiter, left - 1, [entry | acc], common <> <<255>>)

        _ ->
          [{_, etag, size, mtime}] = :ets.lookup(store.objects, key)
          modified = mtime |> DateTime.from_unix!() |> DateTime.to_iso8601()

          entry =
            "<Contents><Key>#{escape(key)}</Key><LastModified>#{modified}</LastModified>" <>
              "<ETag>#{escape(etag)}</ETag><Size>#{size}</Size></Contents>"

          walk(store, :ets.next(store.objects, key), prefix, delimiter, left - 1, [entry | acc], key)
      end
    else
      {Enum.reverse(acc), last, false}
    end
  rescue
    # A concurrent delete between next/lookup: continue after the key.
    MatchError -> walk(store, :ets.next(store.objects, key), prefix, delimiter, left, acc, last)
  end

  defp escape(text),
    do: text |> String.replace("&", "&amp;") |> String.replace("<", "&lt;") |> String.replace(">", "&gt;")
end
