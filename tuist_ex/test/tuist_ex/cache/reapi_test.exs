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

defmodule TuistEx.Cache.ReapiTest.ByteServer do
  use GRPC.Server, service: TuistEx.Cache.Reapi.ByteStream.Service

  alias TuistEx.Cache.ReapiTest.ActionServer

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

    [hash, declared_size] =
      resource |> String.split("/blobs/") |> List.last() |> String.split("/")

    pid = instance |> to_charlist() |> :erlang.list_to_pid()
    ActionServer.capture(pid, stream)
    if Agent.get(pid, &Map.get(&1, :stall_write, false)), do: Process.sleep(:infinity)
    data = chunks |> Enum.reverse() |> IO.iodata_to_binary()

    if String.to_integer(declared_size) != size or
         Base.encode16(:crypto.hash(:sha256, data), case: :lower) != hash,
       do: raise(GRPC.RPCError, status: GRPC.Status.invalid_argument(), message: "digest")

    Agent.update(pid, &put_in(&1, [:blobs, hash], data))

    %Google.Bytestream.WriteResponse{committed_size: size}
  end

  def read(request, stream) do
    [instance | _] = String.split(request.resource_name, "/")

    [hash, _size] =
      request.resource_name |> String.split("/blobs/") |> List.last() |> String.split("/")

    pid = instance |> to_charlist() |> :erlang.list_to_pid()
    ActionServer.capture(pid, stream)

    case Agent.get(pid, &Map.get(&1.blobs, hash)) do
      nil ->
        raise GRPC.RPCError, status: GRPC.Status.not_found(), message: "missing"

      data ->
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
end

defmodule TuistEx.Cache.ReapiTest do
  use ExUnit.Case, async: true

  alias TuistEx.Cache.Key
  alias TuistEx.Cache.Reapi
  alias TuistEx.Cache.ReapiTest.Endpoint

  setup_all do
    start_supervised!(
      {GRPC.Server.Supervisor,
       endpoint: Endpoint, port: 0, start_server: true, adapter_opts: [ip: {127, 0, 0, 1}]}
    )

    %{port: :ranch.get_port(inspect(Endpoint))}
  end

  setup %{port: port} do
    {:ok, store} = Agent.start_link(fn -> %{actions: %{}, blobs: %{}, metadata: []} end)
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
