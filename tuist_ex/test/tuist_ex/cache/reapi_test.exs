defmodule TuistEx.Cache.ReapiTest.ActionServer do
  use GRPC.Server, service: TuistEx.Cache.Reapi.ActionCache.Service

  alias TuistEx.Cache.Reapi.RequestMetadata

  def get_action_result(request, stream) do
    pid = request.instance_name |> to_charlist() |> :erlang.list_to_pid()
    capture(pid, stream)
    if Agent.get(pid, &Map.get(&1, :stall, false)), do: Process.sleep(:infinity)

    case Agent.get(pid, &Map.get(&1.actions, request.action_digest.hash)) do
      nil -> raise GRPC.RPCError, status: GRPC.Status.not_found(), message: "missing"
      result -> result
    end
  end

  def update_action_result(request, stream) do
    pid = request.instance_name |> to_charlist() |> :erlang.list_to_pid()
    capture(pid, stream)

    if Agent.get(pid, &Map.get(&1, :reject_action_update, false)),
      do:
        raise(GRPC.RPCError, status: GRPC.Status.permission_denied(), message: "read-only cache")

    Agent.update(pid, &put_in(&1, [:actions, request.action_digest.hash], request.action_result))
    request.action_result
  end

  def capture(pid, stream) do
    headers = GRPC.Stream.get_headers(stream)

    metadata =
      RequestMetadata.decode(headers["build.bazel.remote.execution.v2.requestmetadata-bin"])

    Agent.update(
      pid,
      &Map.update!(&1, :metadata, fn values -> [{headers, metadata} | values] end)
    )
  end
end

defmodule TuistEx.Cache.ReapiTest.CapabilitiesServer do
  use GRPC.Server, service: TuistEx.Cache.Reapi.Capabilities.Service

  def get_capabilities(request, _stream) do
    pid = request.instance_name |> to_charlist() |> :erlang.list_to_pid()
    Agent.update(pid, &Map.update(&1, :capability_requests, 1, fn count -> count + 1 end))
    if Agent.get(pid, &Map.get(&1, :stall_capabilities, false)), do: Process.sleep(:infinity)

    if Agent.get(pid, &Map.get(&1, :capabilities_unimplemented, false)),
      do: raise(GRPC.RPCError, status: GRPC.Status.unimplemented(), message: "legacy endpoint")

    %TuistEx.Cache.Reapi.ServerCapabilities{
      cache_capabilities: %TuistEx.Cache.Reapi.CacheCapabilities{
        supported_compressors: Agent.get(pid, & &1.compressors)
      }
    }
  end
end

defmodule TuistEx.Cache.ReapiTest.ByteServer do
  use GRPC.Server, service: TuistEx.Cache.Reapi.ByteStream.Service

  alias TuistEx.Cache.Reapi.Compression
  alias TuistEx.Cache.ReapiTest.ActionServer

  @compile {:no_warn_undefined, :zstd}

  def write(requests, stream) do
    {resource, chunks, size, finished} =
      Enum.reduce(requests, {nil, [], 0, false}, fn request, {resource, chunks, offset, _} ->
        if request.write_offset != offset,
          do: raise(GRPC.RPCError, status: GRPC.Status.invalid_argument(), message: "offset")

        {resource || request.resource_name, [request.data | chunks],
         offset + byte_size(request.data), request.finish_write}
      end)

    if !finished,
      do: raise(GRPC.RPCError, status: GRPC.Status.invalid_argument(), message: "unfinished")

    [instance | _] = String.split(resource, "/")

    [hash, declared_size] = resource |> String.split("/") |> Enum.take(-2)
    compressed? = String.contains?(resource, "/compressed-blobs/zstd/")

    pid = instance |> to_charlist() |> :erlang.list_to_pid()
    ActionServer.capture(pid, stream)
    if Agent.get(pid, &Map.get(&1, :stall_write, false)), do: Process.sleep(:infinity)
    wire = chunks |> Enum.reverse() |> IO.iodata_to_binary()

    data =
      if compressed?,
        do: Compression.decompress(wire, String.to_integer(declared_size)),
        else: wire

    Agent.update(pid, &Map.update!(&1, :transfers, fn values -> [{resource, size} | values] end))

    if String.to_integer(declared_size) != byte_size(data) or
         Base.encode16(:crypto.hash(:sha256, data), case: :lower) != hash,
       do: raise(GRPC.RPCError, status: GRPC.Status.invalid_argument(), message: "digest")

    Agent.update(pid, &put_in(&1, [:blobs, hash], data))

    committed_size = Agent.get(pid, &Map.get(&1, :committed_size, size))
    %Google.Bytestream.WriteResponse{committed_size: committed_size}
  end

  def read(request, stream) do
    [instance | _] = String.split(request.resource_name, "/")

    [hash, _size] = request.resource_name |> String.split("/") |> Enum.take(-2)
    compressed? = String.contains?(request.resource_name, "/compressed-blobs/zstd/")

    pid = instance |> to_charlist() |> :erlang.list_to_pid()
    ActionServer.capture(pid, stream)

    case Agent.get(pid, &Map.get(&1.blobs, hash)) do
      nil ->
        raise GRPC.RPCError, status: GRPC.Status.not_found(), message: "missing"

      data ->
        if compressed? and Agent.get(pid, &Map.get(&1, :compressed_read_unimplemented, false)),
          do: raise(GRPC.RPCError, status: GRPC.Status.unimplemented(), message: "chunked blob")

        data =
          if compressed? do
            Agent.get(pid, &Map.get(&1, :compressed_response)) ||
              :zstd.compress(data) |> IO.iodata_to_binary()
          else
            data
          end

        Agent.update(pid, fn state ->
          Map.update!(state, :transfers, &[{request.resource_name, byte_size(data)} | &1])
        end)

        [%Google.Bytestream.ReadResponse{data: data}]
        |> GRPC.Stream.from()
        |> GRPC.Stream.run_with(stream)
    end
  end
end

defmodule TuistEx.Cache.ReapiTest.Endpoint do
  use GRPC.Endpoint

  run(TuistEx.Cache.ReapiTest.ActionServer)
  run(TuistEx.Cache.ReapiTest.ByteServer)
  run(TuistEx.Cache.ReapiTest.CapabilitiesServer)
end

defmodule TuistEx.Cache.ReapiTest do
  use ExUnit.Case, async: true

  alias TuistEx.Cache.Key
  alias TuistEx.Cache.Reapi
  alias TuistEx.Cache.ReapiTest.Endpoint

  @compile {:no_warn_undefined, :zstd}

  setup_all do
    start_supervised!(
      {GRPC.Server.Supervisor,
       endpoint: Endpoint, port: 0, start_server: true, adapter_opts: [ip: {127, 0, 0, 1}]}
    )

    %{port: :ranch.get_port(inspect(Endpoint))}
  end

  setup %{port: port} = context do
    {:ok, store} =
      Agent.start_link(fn ->
        %{
          actions: %{},
          blobs: %{},
          metadata: [],
          transfers: [],
          compressors: if(context[:zstd], do: [1], else: []),
          capabilities_unimplemented: context[:capabilities_unimplemented] || false
        }
      end)

    project = store |> :erlang.pid_to_list() |> List.to_string()

    flags = Process.info(self(), :trap_exit)
    links = Process.info(self(), :links)

    {:ok, session} =
      Reapi.connect(
        "http://127.0.0.1:#{port}",
        "cache-token",
        %{account: "acme", project: project},
        "build-id"
      )

    assert Process.info(self(), :trap_exit) == flags
    assert Process.info(self(), :links) == links
    on_exit(fn -> Reapi.close(session) end)
    %{session: session, store: store}
  end

  test "disables Nagle buffering for separately sent HTTP/2 request frames", %{session: session} do
    conn = :sys.get_state(session.channel.adapter_payload.conn_pid).conn
    socket = Mint.HTTP.get_socket(conn)

    assert {:ok, [nodelay: true]} = :inet.getopts(socket, [:nodelay])
  end

  test "hostname endpoints preserve the HTTP authority and close their channels cleanly", %{
    port: port,
    store: store
  } do
    project = store |> :erlang.pid_to_list() |> List.to_string()

    logs =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, session} =
                 Reapi.connect(
                   "http://localhost:#{port}",
                   "cache-token",
                   %{account: "acme", project: project},
                   "dns-build"
                 )

        assert :sys.get_state(session.channel.adapter_payload.conn_pid).conn.hostname ==
                 "localhost"

        pid = session.channel.adapter_payload.conn_pid
        assert {:ok, _} = Reapi.put(session, Key.build(:dns), :nimble_options, "DNS content")
        assert :ok = Reapi.close(session)
        refute Process.alive?(pid)
      end)

    refute logs =~ "terminating"
  end

  test "resolves private hostnames through the system resolver before selecting an IPv4 target" do
    uri = URI.parse("https://cache.internal:8443")

    resolver = fn ~c"cache.internal", :inet -> {:ok, {192, 0, 2, 42}} end
    assert {:ok, "ipv4:192.0.2.42:8443"} = Reapi.resolve_address(uri, resolver)
  end

  test "falls back to IPv6-only system resolver results" do
    uri = URI.parse("https://cache.internal")

    resolver = fn
      ~c"cache.internal", :inet -> {:error, :nxdomain}
      ~c"cache.internal", :inet6 -> {:ok, {0, 0, 0, 0, 0, 0, 0, 1}}
    end

    assert {:ok, "ipv6:[::1]:443"} = Reapi.resolve_address(uri, resolver)
  end

  test "unresolvable endpoints return an error rather than a malformed gRPC target" do
    resolver = fn ~c"cache.internal", family ->
      send(self(), {:lookup, family})
      {:error, :nxdomain}
    end

    assert {:error, :unavailable} =
             Reapi.resolve_address(URI.parse("https://cache.internal"), resolver)

    assert_received {:lookup, :inet}
    assert_received {:lookup, :inet6}
  end

  test "IPv4 and IPv6 literal endpoints retain explicit resolver targets" do
    assert {:ok, "ipv4:127.0.0.1:443"} =
             Reapi.resolve_address(URI.parse("https://127.0.0.1"))

    assert {:ok, "ipv6:[::1]:443"} = Reapi.resolve_address(URI.parse("https://[::1]"))
  end

  @tag skip: not Code.ensure_loaded?(:zstd)
  test "a capabilities timeout fails the connection instead of returning a closed session", %{
    port: port,
    store: store
  } do
    Agent.update(store, &Map.put(&1, :stall_capabilities, true))
    project = store |> :erlang.pid_to_list() |> List.to_string()

    assert {:error, :unavailable} =
             Reapi.connect(
               "http://localhost:#{port}",
               "cache-token",
               %{account: "acme", project: project},
               "stalled-capabilities"
             )
  end

  test "uses standard REAPI action mappings and streamed CAS content with Mix attribution", %{
    session: session,
    store: store
  } do
    key = Key.build(:action)
    binary = :crypto.strong_rand_bytes(200_000)
    assert :miss = Reapi.get(session, key, :jason)
    assert {:ok, uploaded} = Reapi.put(session, key, :jason, binary)
    assert uploaded.output_digest == Base.encode16(:crypto.hash(:sha256, binary), case: :lower)
    refute uploaded.output_digest == Key.digest(binary)
    assert uploaded.write_bytes == byte_size(binary)
    assert uploaded.write_duration_us > 0
    assert {:ok, ^binary, downloaded} = Reapi.get(session, key, :jason)
    assert downloaded.read_bytes == byte_size(binary)
    assert downloaded.read_duration_us > 0
    assert downloaded.output_digest != key
    metadata = Agent.get(store, & &1.metadata)
    assert length(metadata) == 5

    for {headers, metadata} <- metadata do
      assert headers["authorization"] == "Bearer cache-token"
      assert headers["x-tuist-account-handle"] == "acme"
      assert metadata.tool_details.tool_name == "mix"
      assert metadata.tool_invocation_id == "build-id"
      assert metadata.target_id == "jason"
      assert metadata.action_id == key
    end
  end

  @tag zstd: true, skip: not Code.ensure_loaded?(:zstd)
  test "negotiates zstd once and transfers compressed bytes with uncompressed CAS digests", %{
    session: session,
    store: store
  } do
    binary =
      :crypto.strong_rand_bytes(100_000) <> String.duplicate("compiled BEAM content", 100_000)

    key = Key.build(:compressed)
    assert session.zstd
    assert {:ok, uploaded} = Reapi.put(session, key, :nimble_options, binary)
    assert {:ok, ^binary, downloaded} = Reapi.get(session, key, :nimble_options)
    assert uploaded.write_bytes == byte_size(binary)
    assert downloaded.read_bytes == byte_size(binary)
    assert Agent.get(store, & &1.capability_requests) == 1
    transfers = Agent.get(store, & &1.transfers)
    assert length(transfers) == 2

    for {resource, size} <- transfers do
      assert resource =~ "/compressed-blobs/zstd/"
      assert resource =~ uploaded.output_digest
      assert String.ends_with?(resource, "/#{byte_size(binary)}")
      assert size < div(byte_size(binary), 10)
    end
  end

  @tag zstd: true, skip: not Code.ensure_loaded?(:zstd)
  test "incompressible uploads use identity and compressed reads can fall back for chunked blobs",
       %{
         session: session,
         store: store
       } do
    binary = :crypto.strong_rand_bytes(200_000)
    key = Key.build(:identity)
    assert {:ok, _} = Reapi.put(session, key, :nimble_options, binary)
    assert [{resource, 200_000}] = Agent.get(store, & &1.transfers)
    refute resource =~ "compressed-blobs"
    Agent.update(store, &Map.put(&1, :compressed_read_unimplemented, true))
    assert {:ok, ^binary, _} = Reapi.get(session, key, :nimble_options)
    assert Process.alive?(session.channel.adapter_payload.conn_pid)
  end

  @tag zstd: true, skip: not Code.ensure_loaded?(:zstd)
  test "small blobs retain identity transport", %{session: session, store: store} do
    binary = String.duplicate("BEAM", 200)
    key = Key.build(:small)
    assert {:ok, _} = Reapi.put(session, key, :nimble_options, binary)
    assert {:ok, ^binary, _} = Reapi.get(session, key, :nimble_options)

    for {resource, size} <- Agent.get(store, & &1.transfers) do
      refute resource =~ "compressed-blobs"
      assert size == byte_size(binary)
    end
  end

  @tag capabilities_unimplemented: true
  test "legacy endpoints without capabilities retain identity transport", %{
    session: session,
    store: store
  } do
    refute session.zstd
    binary = String.duplicate("BEAM", 10_000)
    key = Key.build(:legacy)
    assert {:ok, _} = Reapi.put(session, key, :nimble_options, binary)
    assert {:ok, ^binary, _} = Reapi.get(session, key, :nimble_options)

    for {resource, _size} <- Agent.get(store, & &1.transfers) do
      refute resource =~ "compressed-blobs"
    end
  end

  @tag zstd: true, skip: not Code.ensure_loaded?(:zstd)
  test "invalid compressed upload acknowledgements never publish action mappings or metrics", %{
    session: session,
    store: store
  } do
    binary = String.duplicate("BEAM", 10_000)
    key = Key.build(:invalid_commit)

    for size <- [0, byte_size(binary), -2] do
      Agent.update(store, &Map.put(&1, :committed_size, size))
      assert {:error, :unavailable} = Reapi.put(session, key, :nimble_options, binary)
      assert Agent.get(store, & &1.actions) == %{}
    end
  end

  test "identity uploads reject partial and compressed-only acknowledgements", %{
    session: session,
    store: store
  } do
    for size <- [0, -1] do
      Agent.update(store, &Map.put(&1, :committed_size, size))
      assert {:error, :unavailable} = Reapi.put(session, Key.build(size), :jason, "BEAM")
      assert Agent.get(store, & &1.actions) == %{}
    end
  end

  test "a failed action update does not report a successful upload", %{
    session: session,
    store: store
  } do
    Agent.update(store, &Map.put(&1, :reject_action_update, true))
    assert {:error, :unavailable} = Reapi.put(session, Key.build(:read_only), :jason, "BEAM")
    assert Agent.get(store, & &1.actions) == %{}
  end

  @tag zstd: true, skip: not Code.ensure_loaded?(:zstd)
  test "accepts concurrent compressed upload completion without changing the action digest", %{
    session: session,
    store: store
  } do
    Agent.update(store, &Map.put(&1, :committed_size, -1))
    binary = String.duplicate("BEAM", 10_000)
    key = Key.build(:concurrent)
    assert {:ok, _} = Reapi.put(session, key, :nimble_options, binary)
    assert {:ok, ^binary, _} = Reapi.get(session, key, :nimble_options)
  end

  for corruption <- [:oversized, :truncated, :digest_mismatch] do
    @tag zstd: true, skip: not Code.ensure_loaded?(:zstd)
    test "rejects #{corruption} compressed reads and closes the transport", %{
      session: session,
      store: store
    } do
      binary = String.duplicate("BEAM", 10_000)
      key = Key.build(unquote(corruption))
      assert {:ok, _} = Reapi.put(session, key, :nimble_options, binary)

      response =
        case unquote(corruption) do
          :oversized ->
            :zstd.compress(binary <> "extra") |> IO.iodata_to_binary()

          :truncated ->
            compressed = :zstd.compress(binary) |> IO.iodata_to_binary()
            binary_part(compressed, 0, byte_size(compressed) - 1)

          :digest_mismatch ->
            :zstd.compress(String.duplicate("DIFF", 10_000)) |> IO.iodata_to_binary()
        end

      Agent.update(store, &Map.put(&1, :compressed_response, response))
      assert :miss = Reapi.get(session, key, :nimble_options)
      refute Process.alive?(session.channel.adapter_payload.conn_pid)
    end
  end

  test "a server ignoring the RPC deadline cannot block the compiler", %{
    session: session,
    store: store
  } do
    Agent.update(store, &Map.put(&1, :stall, true))
    started = System.monotonic_time(:millisecond)
    assert :miss = Reapi.get(session, Key.build(:stalled), :jason, 100)
    assert System.monotonic_time(:millisecond) - started < 2_000
    refute Process.alive?(session.channel.adapter_payload.conn_pid)
  end

  test "a stalled upload fails open without publishing its action result", %{
    session: session,
    store: store
  } do
    Agent.update(store, &Map.put(&1, :stall_write, true))
    key = Key.build(:stalled_upload)
    assert {:error, :timeout} = Reapi.put(session, key, :jason, "real-content", 100)
    assert Agent.get(store, & &1.actions) == %{}
    refute Process.alive?(session.channel.adapter_payload.conn_pid)
  end

  test "non-loopback cleartext endpoints are rejected before sending credentials" do
    assert catch_throw(
             Reapi.connect(
               "http://cache.example.com",
               "secret",
               %{account: "acme", project: "app"},
               "build"
             )
           ) == :invalid_endpoint
  end

  test "unused cache sessions never resolve credentials or open network connections" do
    options = [environment: fn _ -> flunk("unused transport resolved configuration") end]
    assert :local_hit = Reapi.with_session([], "local-build", options, fn _ -> :local_hit end)
  end

  test "an unavailable session is resolved once and cleaned up after compiler failure" do
    keys = Process.get_keys()
    owner = self()

    options = [
      environment: fn key ->
        send(owner, {:configuration, key})
        "invalid-server-url"
      end
    ]

    assert_raise RuntimeError, "compiler failure", fn ->
      Reapi.with_session([], "build", options, fn remote ->
        assert remote.() == nil
        assert remote.() == nil
        raise "compiler failure"
      end)
    end

    assert_receive {:configuration, "TUIST_URL"}
    refute_receive {:configuration, _}
    assert MapSet.new(Process.get_keys()) == MapSet.new(keys)
  end

  test "cache token scope follows the compile reporting URL and project overrides", %{
    port: port,
    store: store
  } do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, http_port} = :inet.port(listener)
    project = "acme/" <> (store |> :erlang.pid_to_list() |> List.to_string())

    request =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5_000)
        {:ok, request} = :gen_tcp.recv(socket, 0, 5_000)
        body = JSON.encode!(%{token: "scoped-cache-token"})

        :ok =
          :gen_tcp.send(
            socket,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n" <>
              body
          )

        :gen_tcp.close(socket)
        request
      end)

    on_exit(fn -> :gen_tcp.close(listener) end)

    options = [
      url: "http://127.0.0.1:#{http_port}",
      project: project,
      environment: fn
        "TUIST_TOKEN" -> "api-token"
        _ -> nil
      end
    ]

    assert {:ok, session} =
             Reapi.open([endpoint: "http://127.0.0.1:#{port}"], "override-build", options)

    on_exit(fn -> Reapi.close(session) end)
    assert session.account == "acme"
    assert "acme/" <> session.project == project
    assert session.invocation_id == "override-build"
    request = Task.await(request)
    assert request =~ "/api/cache/token?" <> URI.encode_query(%{"full_handle" => project})
    assert String.downcase(request) =~ "authorization: bearer api-token"
  end

  test "endpoint discovery requests Kura using the shared client feature flag header", %{
    port: port,
    store: store
  } do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, http_port} = :inet.port(listener)
    project = "acme/" <> (store |> :erlang.pid_to_list() |> List.to_string())

    requests =
      Task.async(fn ->
        for response <- [%{endpoints: ["http://127.0.0.1:#{port}"]}, %{token: "scoped-token"}] do
          {:ok, socket} = :gen_tcp.accept(listener, 5_000)
          {:ok, request} = :gen_tcp.recv(socket, 0, 5_000)
          body = JSON.encode!(response)

          :ok =
            :gen_tcp.send(
              socket,
              "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n" <>
                body
            )

          :gen_tcp.close(socket)
          request
        end
      end)

    on_exit(fn -> :gen_tcp.close(listener) end)

    options = [
      url: "http://127.0.0.1:#{http_port}",
      project: project,
      environment: fn
        "TUIST_TOKEN" -> "api-token"
        _ -> nil
      end
    ]

    assert {:ok, session} = Reapi.open([], "discovered-build", options)
    on_exit(fn -> Reapi.close(session) end)
    [discovery, token] = Task.await(requests)
    assert discovery =~ "/api/cache/endpoints?account_handle=acme"
    assert String.downcase(discovery) =~ "x-tuist-feature-flags: kura"
    refute String.downcase(discovery) =~ "x-tuist-client-feature-flags"
    assert token =~ "/api/cache/token?"
    assert session.project == store |> :erlang.pid_to_list() |> List.to_string()
  end

  test "evicted CAS content is a recoverable miss and does not disable later uploads", %{
    session: session,
    store: store
  } do
    key = Key.build(:evicted)
    assert {:ok, uploaded} = Reapi.put(session, key, :decimal, "evicted-content")

    Agent.update(
      store,
      &Map.update!(&1, :blobs, fn blobs -> Map.delete(blobs, uploaded.output_digest) end)
    )

    assert :miss = Reapi.get(session, key, :decimal)
    assert Process.alive?(session.channel.adapter_payload.conn_pid)
    assert {:ok, _} = Reapi.put(session, key, :decimal, "evicted-content")
    assert {:ok, "evicted-content", _} = Reapi.get(session, key, :decimal)
    later = Key.build(:later)
    assert {:ok, _} = Reapi.put(session, later, :jason, "later-content")
    assert {:ok, "later-content", _} = Reapi.get(session, later, :jason)
  end

  test "missing and corrupt CAS blobs fail open instead of returning false hits", %{
    session: session,
    store: store
  } do
    key = Key.build(:action)
    assert {:ok, metrics} = Reapi.put(session, key, :decimal, "real-content")
    Agent.update(store, &put_in(&1, [:blobs, metrics.output_digest], "bad-content!"))
    assert :miss = Reapi.get(session, key, :decimal)

    Agent.update(
      store,
      &put_in(&1, [:blobs, metrics.output_digest], "larger than the advertised blob")
    )

    assert :miss = Reapi.get(session, key, :decimal)

    Agent.update(
      store,
      &Map.update!(&1, :blobs, fn blobs -> Map.delete(blobs, metrics.output_digest) end)
    )

    assert :miss = Reapi.get(session, key, :decimal)
  end
end
