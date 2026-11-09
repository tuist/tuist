defmodule Pulse.Test.CompactionStore do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    conn = fetch_query_params(conn)
    agent = Keyword.fetch!(opts, :agent)
    key = conn.request_path |> URI.decode() |> String.trim_leading("/pulse/")
    {body, conn} = read_full_body(conn, [])

    if hook = Keyword.get(opts, :before_request), do: hook.(conn.method, key, body)

    {status, etag, response} =
      Agent.get_and_update(agent, fn state ->
        dispatch(conn.method, key, body, conn, apply_hook(state, conn.method, key))
      end)

    await_barrier(agent, conn.method, key)
    conn = if etag, do: put_resp_header(conn, "etag", etag), else: conn

    case response do
      {:range, first, size, bytes} ->
        conn |> put_resp_header("content-range", "bytes #{first}-#{size - 1}/#{size}") |> send_resp(status, bytes)

      bytes ->
        send_resp(conn, status, bytes)
    end
  end

  defp read_full_body(conn, chunks) do
    case read_body(conn, length: 16_000_000) do
      {:more, chunk, conn} -> read_full_body(conn, [chunk | chunks])
      {:ok, chunk, conn} -> {IO.iodata_to_binary(Enum.reverse([chunk | chunks])), conn}
    end
  end

  defp await_barrier(agent, method, key) do
    selector = if String.contains?(key, "-compact-"), do: :replacement, else: key

    case Agent.get(agent, &barrier_owner(&1, method, key, selector)) do
      nil ->
        :ok

      owner ->
        send(owner, {:storage_barrier, self(), method, key})

        receive do
          {:release_storage, ^key} -> :ok
        after
          10_000 -> raise "storage barrier was not released"
        end
    end
  end

  # `:segment` holds ingested segments, `:replacement` compaction outputs and
  # `:page` format-4 manifest pages.
  defp barrier_owner(state, method, key, selector) do
    Map.get(state.barriers, {method, selector}) ||
      cond do
        String.ends_with?(key, ".parquet") and selector != :replacement -> Map.get(state.barriers, {method, :segment})
        String.contains?(key, "/journal/") -> Map.get(state.barriers, {method, :page})
        true -> nil
      end
  end

  # Faults exercise the native client's real retry and conditional-write path.
  defp dispatch(method, key, body, conn, state) do
    state = %{state | requests: [{method, key} | state.requests]}
    selector = if String.contains?(key, "-compact-"), do: :replacement, else: key
    fault_key = {method, selector}

    case Map.get(state.faults, fault_key) do
      nil ->
        request(method, key, body, conn, state)

      {status, phase, remaining} ->
        faults =
          if remaining == 1,
            do: Map.delete(state.faults, fault_key),
            else: Map.put(state.faults, fault_key, {status, phase, remaining - 1})

        apply_fault(status, phase, method, key, body, conn, %{state | faults: faults})
    end
  end

  defp apply_fault(status, :before, _method, _key, _body, _conn, state), do: {{status, nil, ""}, state}

  defp apply_fault(status, :after, method, key, body, conn, state) do
    {_response, state} = request(method, key, body, conn, state)
    {{status, nil, ""}, state}
  end

  defp apply_hook(state, method, key) do
    if method == "PUT" and String.ends_with?(key, "manifest.json") and state.hook,
      do: state.hook.(%{state | hook: nil}),
      else: state
  end

  defp request("PUT", key, body, conn, state) do
    object = Map.get(state.objects, key)
    match = List.first(get_req_header(conn, "if-match"))
    none = List.first(get_req_header(conn, "if-none-match"))

    if (match != nil and (is_nil(object) or elem(object, 0) != match)) or (none == "*" and object != nil) do
      # Lost conditional writes of a root, for tests asserting there were none.
      state =
        if String.ends_with?(key, "manifest.json"),
          do: Map.update(state, :manifest_conflicts, 1, &(&1 + 1)),
          else: state

      {{412, nil, ""}, state}
    else
      etag = "\"#{state.version + 1}\""
      {{200, etag, ""}, %{state | objects: Map.put(state.objects, key, {etag, body}), version: state.version + 1}}
    end
  end

  defp request("GET", key, _body, conn, state) do
    state = %{
      state
      | reads: [key | state.reads],
        lists: state.lists + if(Map.has_key?(conn.query_params, "list-type"), do: 1, else: 0)
    }

    none = List.first(get_req_header(conn, "if-none-match"))
    match = List.first(get_req_header(conn, "if-match"))
    range = List.first(get_req_header(conn, "range"))

    state = record_range_request(state, key, range, match)

    case Map.get(state.objects, key) do
      nil when is_map_key(conn.query_params, "list-type") ->
        {{200, nil, list_response(state, conn)}, state}

      nil ->
        {{404, nil, ""}, state}

      {etag, _} when match != nil and etag != match ->
        {{412, etag, ""}, state}

      {etag, _} when etag == none ->
        {{304, etag, ""}, state}

      {etag, body} when is_binary(range) ->
        suffix_response(state, etag, body, range)

      {etag, body} ->
        {{200, etag, body}, state}
    end
  end

  defp request("DELETE", key, _body, _conn, state),
    do: {{204, nil, ""}, %{state | objects: Map.delete(state.objects, key), deletes: [key | state.deletes]}}

  defp record_range_request(state, key, range, match) do
    if range || match,
      do: Map.update(state, :range_requests, [{key, range, match}], &[{key, range, match} | &1]),
      else: state
  end

  defp suffix_response(state, etag, body, range) do
    case Integer.parse(String.replace_prefix(range, "bytes=-", "")) do
      {suffix, ""} when suffix > 0 ->
        first = max(0, byte_size(body) - suffix)
        bytes = binary_part(body, first, byte_size(body) - first)
        {{206, etag, {:range, first, byte_size(body), bytes}}, state}

      _ ->
        {{416, etag, ""}, state}
    end
  end

  defp list_response(state, conn) do
    prefix = Map.get(conn.query_params, "prefix", "")

    after_key = Map.get(conn.query_params, "start-after", "")

    keys =
      state.objects |> Map.keys() |> Enum.filter(&(String.starts_with?(&1, prefix) and &1 > after_key)) |> Enum.sort()

    {entries, truncated, token} =
      if Map.get(conn.query_params, "delimiter") == "/" do
        prefixes =
          keys
          |> Enum.flat_map(fn key ->
            key
            |> String.replace_prefix(prefix, "")
            |> String.split("/", parts: 2)
            |> case do
              [tenant, _rest] -> [prefix <> tenant <> "/"]
              _ -> []
            end
          end)
          |> Enum.uniq()

        # Deliberately small pages exercise the native provider continuation path.
        offset = conn.query_params |> Map.get("continuation-token", "0") |> String.to_integer()
        page = Enum.slice(prefixes, offset, 2)
        truncated = offset + length(page) < length(prefixes)
        entries = Enum.map_join(page, &"<CommonPrefixes><Prefix>#{&1}</Prefix></CommonPrefixes>")
        token = if truncated, do: "<NextContinuationToken>#{offset + length(page)}</NextContinuationToken>", else: ""
        {entries, truncated, token}
      else
        offset = conn.query_params |> Map.get("continuation-token", "0") |> String.to_integer()
        maximum = min(3, conn.query_params |> Map.get("max-keys", "1000") |> String.to_integer())
        page = Enum.slice(keys, offset, maximum)
        truncated = offset + length(page) < length(keys)
        token = if truncated, do: "<NextContinuationToken>#{offset + length(page)}</NextContinuationToken>", else: ""
        {Enum.map_join(page, &list_entry({&1, Map.fetch!(state.objects, &1)})), truncated, token}
      end

    "<ListBucketResult><Name>pulse</Name><IsTruncated>#{truncated}</IsTruncated>#{token}#{entries}</ListBucketResult>"
  end

  defp list_entry({key, {etag, body}}) do
    "<Contents><Key>#{key}</Key><LastModified>2026-10-01T00:00:00Z</LastModified>" <>
      "<ETag>#{etag}</ETag><Size>#{byte_size(body)}</Size></Contents>"
  end
end
