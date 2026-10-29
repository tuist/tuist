defmodule Tuist.Kura.UsageIngestionTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.IngestRepo
  alias Tuist.KeyValueStore.LoadLimiter
  alias Tuist.Kura.Identity
  alias Tuist.Kura.StorageSnapshot
  alias Tuist.Kura.Usage
  alias Tuist.Kura.UsageEvent
  alias Tuist.Projects

  setup :set_mimic_from_context

  setup context do
    name = Module.concat(__MODULE__, "Pool#{System.unique_integer([:positive])}")

    start_supervised!(
      {LoadLimiter,
       name: name, max_concurrency: 1, max_pending_loads: 1, load_timeout: Map.get(context, :load_timeout, 3_000)}
    )

    stub(Identity, :account_ids, fn _ -> %{} end)
    stub(Projects, :project_ids_by_account_and_handle, fn _ -> %{} end)
    %{limiter: name}
  end

  test "validates every array before any write", %{limiter: limiter} do
    reject(IngestRepo, :insert_all, 3)

    assert {:error, :too_many_events} =
             Usage.ingest_batch([event()], [], List.duplicate(%{}, 5_001), nil, limiter: limiter)

    assert {:error, :invalid_payload} = Usage.ingest_batch([event()], [42], [], nil, limiter: limiter)
  end

  @tag load_timeout: 30
  test "retains whole-batch admission after the response times out", %{limiter: limiter} do
    parent = self()

    stub(IngestRepo, :insert_all, fn UsageEvent, [_row], _opts ->
      send(parent, {:inserting, self()})
      receive do: (:finish -> {1, nil})
    end)

    first = Task.async(fn -> Usage.ingest_batch([event()], [], [], nil, limiter: limiter) end)
    assert_receive {:inserting, worker}
    assert Task.await(first) == {:error, :timeout}

    assert Usage.ingest_batch([event()], [], [], nil, limiter: limiter) == {:error, :overloaded}
    assert Process.alive?(worker)
    monitor = Process.monitor(worker)
    send(worker, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}
  end

  test "mixed inserts share one deadline and do not acknowledge a partial commit", %{limiter: limiter} do
    parent = self()

    stub(IngestRepo, :insert_all, fn schema, rows, opts ->
      send(parent, {:insert, schema, opts})
      if schema == StorageSnapshot, do: raise(DBConnection.ConnectionError, "unavailable")
      {length(rows), nil}
    end)

    assert {:error, _} = Usage.ingest_batch([event()], [], [%{}], nil, limiter: limiter)
    assert_receive {:insert, UsageEvent, usage_opts}
    assert_receive {:insert, StorageSnapshot, snapshot_opts}
    assert usage_opts[:deadline] == snapshot_opts[:deadline]
    assert usage_opts[:retry] == false
    assert usage_opts[:checkout_retries] == 0
    assert usage_opts[:queue] == false
    assert usage_opts[:settings][:async_insert] == 0
  end

  @tag :capture_log
  test "an ambiguous driver disconnect is not replayed inside the server", %{limiter: limiter} do
    parent = self()
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, packet: :http_bin, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(listener)
    server = spawn_link(fn -> accept_clickhouse(listener, parent) end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      Process.exit(server, :shutdown)
    end)

    repo =
      start_supervised!(
        {IngestRepo,
         name: nil,
         url: nil,
         hostname: "127.0.0.1",
         port: port,
         pool: DBConnection.ConnectionPool,
         pool_size: 1,
         database: "test",
         settings: [async_insert: 1, wait_for_async_insert: 0]}
      )

    # The handshake has to finish before try-only admission can use this pool.
    previous = IngestRepo.put_dynamic_repo(repo)

    try do
      IngestRepo.checkout(fn -> :ok end)
    after
      IngestRepo.put_dynamic_repo(previous)
    end

    stub(IngestRepo, :insert_all, fn schema, rows, opts ->
      IngestRepo.put_dynamic_repo(repo)
      Mimic.call_original(IngestRepo, :insert_all, [schema, rows, opts])
    end)

    assert {:error, _} = Usage.ingest_batch([event()], [], [], nil, limiter: limiter)
    assert_received {:insert_attempt, query, body}
    assert query["async_insert"] == "0"
    assert body =~ "kura_usage_events"
    refute_received {:insert_attempt, _, _}
  end

  defp accept_clickhouse(listener, parent) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        serve_clickhouse(socket, parent)
        accept_clickhouse(listener, parent)

      {:error, :closed} ->
        :ok
    end
  end

  defp serve_clickhouse(socket, parent) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, {:http_request, :POST, {:abs_path, path}, _version}} ->
        headers = http_headers(socket, %{})
        :ok = :inet.setopts(socket, packet: :raw)
        {:ok, body} = :gen_tcp.recv(socket, String.to_integer(headers["content-length"]), 5_000)

        if String.starts_with?(body, "select 1, version()") do
          types = ["UInt8", "String"]

          response =
            IO.iodata_to_binary([
              Ch.RowBinary.encode_names_and_types(["1", "version()"], types),
              Ch.RowBinary.encode_row([1, "26.3.0"], types)
            ])

          :ok =
            :gen_tcp.send(socket, [
              "HTTP/1.1 200 OK\r\nX-ClickHouse-Format: RowBinaryWithNamesAndTypes\r\nContent-Length: ",
              Integer.to_string(byte_size(response)),
              "\r\n\r\n",
              response
            ])

          :ok = :inet.setopts(socket, packet: :http_bin)
          serve_clickhouse(socket, parent)
        else
          send(parent, {:insert_attempt, URI.decode_query(URI.parse(path).query), body})
          # The insert arrived, but its success response was lost.
          :gen_tcp.close(socket)
        end

      {:error, :closed} ->
        :ok
    end
  end

  defp http_headers(socket, headers) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, {:http_header, _, key, _, value}} ->
        http_headers(socket, Map.put(headers, String.downcase(to_string(key)), value))

      {:ok, :http_eoh} ->
        headers
    end
  end

  defp event do
    %{
      "event_id" => "bounded-batch",
      "tenant_id" => "acme",
      "namespace_id" => "ios",
      "node_id" => "node",
      "region" => "eu-west",
      "traffic_plane" => "peer",
      "direction" => "egress",
      "operation" => "download",
      "protocol" => "http",
      "artifact_kind" => "module",
      "bytes" => 123,
      "request_count" => 1,
      "window_start_unix_seconds" => 1_777_968_000,
      "window_seconds" => 60
    }
  end
end
