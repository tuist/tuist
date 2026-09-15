defmodule Tuist.Application.EndpointDrainerTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Application.EndpointDrainer

  @application :tuist_endpoint_drainer_test
  @oban_name __MODULE__.Oban

  defmodule Worker do
    @moduledoc false
    use Oban.Worker, queue: :shutdown_test

    alias Tuist.Application.EndpointDrainerTest.Endpoint

    @impl true
    def perform(%Oban.Job{args: %{"test_pid" => encoded} = args}) do
      test_pid = encoded |> String.to_charlist() |> :erlang.list_to_pid()
      send(test_pid, {:worker_started, self()})

      if args["wait"] do
        receive do
          :finish -> :ok
        after
          5_000 -> raise "worker was not released by the test"
        end
      end

      send(test_pid, {:performed, Phoenix.Token.sign(Endpoint, "shutdown-test", "payload")})
      :ok
    end
  end

  defmodule Socket do
    use Phoenix.Socket

    @impl true
    def connect(_params, socket, _connect_info), do: {:ok, socket}

    @impl true
    def id(_socket), do: nil
  end

  defmodule Endpoint do
    use Phoenix.Endpoint, otp_app: :tuist

    socket "/socket", Tuist.Application.EndpointDrainerTest.Socket,
      websocket: true,
      longpoll: false,
      drainer: [batch_interval: 1]

    plug :respond

    defp respond(conn, _opts) do
      send(config(:test_pid), {:request_started, self()})

      receive do
        :enqueue ->
          {:ok, _job} =
            Oban.insert(
              Tuist.Application.EndpointDrainerTest.Oban,
              Worker.new(%{test_pid: :test_pid |> config() |> :erlang.pid_to_list() |> to_string()})
            )

          Plug.Conn.send_resp(conn, 200, "Enqueued")
      after
        5_000 -> raise "request was not released by the test"
      end
    end
  end

  defmodule TestApplication do
    @moduledoc false
    use Application

    alias Tuist.Application.EndpointDrainerTest.Endpoint
    alias Tuist.Repo

    @impl true
    def start(_type, {test_pid, server?}) do
      children = [
        {Endpoint,
         server: server?,
         adapter: Bandit.PhoenixAdapter,
         http: [ip: :loopback, port: 0, thousand_island_options: [num_acceptors: 1, shutdown_timeout: 5_000]],
         url: [host: "localhost", port: 80],
         secret_key_base: String.duplicate("a", 64),
         pubsub_server: Tuist.PubSub,
         test_pid: test_pid},
        {Oban,
         name: Tuist.Application.EndpointDrainerTest.Oban,
         repo: Repo,
         notifier: Oban.Notifiers.Isolated,
         peer: false,
         plugins: false,
         queues: [shutdown_test: 1, intentionally_paused: [limit: 1, paused: true]],
         dispatch_cooldown: 1}
      ]

      {:ok, supervisor} = Supervisor.start_link(children, strategy: :one_for_one)
      {:ok, supervisor, test_pid}
    end

    @impl true
    def prep_stop(test_pid) do
      :ok = EndpointDrainer.drain(Endpoint)
      send(test_pid, :web_drained)
      test_pid
    end
  end

  setup tags do
    :ok =
      :application.load(
        {:application, @application, vsn: ~c"1", applications: [:kernel, :stdlib, :elixir],
         mod: {TestApplication, {self(), tags[:server] != false}}}
      )

    on_exit(fn ->
      Application.stop(@application)
      Application.unload(@application)
    end)

    :ok = Application.start(@application)

    if tags[:server] == false do
      :ok
    else
      {:ok, {_address, port}} = Endpoint.server_info(:http)
      %{port: port}
    end
  end

  test "finishes an in-flight job insertion before stopping Oban", %{port: port} do
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 1_000)
    :ok = :gen_tcp.send(socket, "POST /enqueue HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n")
    assert_receive {:request_started, handler}, 1_000

    shutdown = Task.async(fn -> Application.stop(@application) end)

    wait_until(fn -> :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 100) end, fn
      {:error, reason} when reason in [:econnrefused, :econnreset] ->
        true

      {:ok, connection} ->
        :gen_tcp.close(connection)
        false
    end)

    assert Oban.whereis(@oban_name)
    assert Task.yield(shutdown, 0) == nil
    send(handler, :enqueue)
    assert {:ok, response} = :gen_tcp.recv(socket, 0, 1_000)
    assert response =~ "200 OK"
    assert :ok = Task.await(shutdown)
    assert Oban.whereis(@oban_name) == nil
    :gen_tcp.close(socket)
  end

  test "retains endpoint configuration until running jobs finish" do
    insert_job(wait: true)
    assert_receive {:worker_started, worker}, 2_000

    shutdown = Task.async(fn -> Application.stop(@application) end)
    assert_receive :web_drained, 2_000
    assert Process.alive?(worker)
    assert Task.yield(shutdown, 0) == nil

    send(worker, :finish)
    assert_receive {:performed, token}, 2_000
    assert is_binary(token)
    assert :ok = Task.await(shutdown)
    assert Process.whereis(Endpoint) == nil
  end

  test "restores configured queues after an internal Oban restart" do
    insert_job()
    assert_receive {:performed, _}, 2_000
    oban = Oban.whereis(@oban_name)
    endpoint = Process.whereis(Endpoint)
    nursery = Oban.Registry.whereis(@oban_name, Oban.Nursery)
    :ok = Supervisor.stop(nursery, :shutdown)

    wait_until(fn -> Oban.Registry.whereis(@oban_name, Oban.Nursery) end, fn pid ->
      is_pid(pid) and pid != nursery
    end)

    assert Oban.whereis(@oban_name) == oban
    assert Process.whereis(Endpoint) == endpoint
    assert Oban.config(@oban_name).queues[:shutdown_test][:limit] == 1
    insert_job()
    assert_receive {:performed, _}, 2_000
    assert %{paused: true} = Oban.check_queue(@oban_name, queue: :intentionally_paused)
  end

  test "drains socket connections while endpoint configuration remains available", %{port: port} do
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 1_000)

    :ok =
      :gen_tcp.send(socket, [
        "GET /socket/websocket?vsn=2.0.0 HTTP/1.1\r\n",
        "Host: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n",
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
      ])

    assert {:ok, response} = :gen_tcp.recv(socket, 0, 1_000)
    assert response =~ "101 Switching Protocols"
    assert :ok = EndpointDrainer.drain(Endpoint)
    assert {:ok, <<0x88, _length, 1000::16, _rest::binary>>} = :gen_tcp.recv(socket, 0, 1_000)
    assert is_binary(Phoenix.Token.sign(Endpoint, "shutdown-test", "payload"))
    :gen_tcp.close(socket)
  end

  @tag server: false
  test "supports endpoints without a server and repeated draining" do
    assert :ok = EndpointDrainer.drain(Endpoint)
    assert :ok = EndpointDrainer.drain(Endpoint)
    assert is_binary(Phoenix.Token.sign(Endpoint, "shutdown-test", "payload"))
    insert_job()
    assert_receive {:performed, _}, 2_000
  end

  defp insert_job(opts \\ []) do
    assert {:ok, _} =
             Oban.insert(
               @oban_name,
               Worker.new(%{test_pid: self() |> :erlang.pid_to_list() |> to_string(), wait: opts[:wait] || false})
             )
  end

  defp wait_until(fetch, matches?, attempts \\ 100) do
    value = fetch.()

    if matches?.(value) do
      value
    else
      assert attempts > 0
      Process.sleep(10)
      wait_until(fetch, matches?, attempts - 1)
    end
  end
end
