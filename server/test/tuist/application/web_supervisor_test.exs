defmodule Tuist.Application.WebSupervisorTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Application.WebSupervisor

  @oban_name __MODULE__.Oban

  defmodule Worker do
    @moduledoc false
    use Oban.Worker, queue: :shutdown_test

    alias Tuist.Application.WebSupervisorTest.Endpoint

    @impl true
    def perform(%Oban.Job{args: %{"test_pid" => test_pid}}) do
      test_pid |> String.to_charlist() |> :erlang.list_to_pid() |> send({:performed, Endpoint.url()})
      :ok
    end
  end

  defmodule Endpoint do
    use Phoenix.Endpoint, otp_app: :tuist

    plug :respond

    defp respond(conn, _opts) do
      send(config(:test_pid), {:request_started, self()})

      receive do
        :enqueue ->
          {:ok, _job} =
            Oban.insert(
              Tuist.Application.WebSupervisorTest.Oban,
              Worker.new(%{test_pid: :test_pid |> config() |> :erlang.pid_to_list() |> to_string()})
            )

          Plug.Conn.send_resp(conn, 200, "Enqueued")
      after
        5_000 -> raise "request was not released by the test"
      end
    end
  end

  setup do
    endpoint = %{
      id: Endpoint,
      start: {__MODULE__, :start_endpoint, [self()]},
      type: :supervisor
    }

    supervisor =
      start_supervised!(
        {WebSupervisor,
         oban: [
           name: @oban_name,
           repo: Repo,
           notifier: Oban.Notifiers.Isolated,
           peer: false,
           plugins: false,
           queues: [shutdown_test: 1, intentionally_paused: [limit: 1, paused: true]],
           dispatch_cooldown: 1
         ],
         endpoint: endpoint}
      )

    assert_receive {:endpoint_starting, nil}
    assert_receive {:performed, "http://localhost"}, 5_000
    {:ok, {_address, port}} = Endpoint.server_info(:http)

    %{supervisor: supervisor, port: port}
  end

  def start_endpoint(test_pid) do
    send(test_pid, {:endpoint_starting, Oban.check_queue(@oban_name, queue: :shutdown_test)})
    {:ok, _job} = Oban.insert(@oban_name, Worker.new(%{test_pid: test_pid |> :erlang.pid_to_list() |> to_string()}))

    Endpoint.start_link(
      server: true,
      adapter: Bandit.PhoenixAdapter,
      http: [ip: :loopback, port: 0, thousand_island_options: [num_acceptors: 1, shutdown_timeout: 5_000]],
      url: [host: "localhost", port: 80],
      secret_key_base: String.duplicate("a", 64),
      test_pid: test_pid
    )
  end

  test "starts queues only after the endpoint and preserves explicitly paused queues" do
    assert %{paused: false, limit: 1} = Oban.check_queue(@oban_name, queue: :shutdown_test)

    assert %{paused: true, limit: 1} =
             wait_until(fn -> Oban.check_queue(@oban_name, queue: :intentionally_paused) end, &is_map/1)
  end

  test "finishes an in-flight job insertion before stopping Oban", %{supervisor: supervisor, port: port} do
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 1_000)
    :ok = :gen_tcp.send(socket, "POST /enqueue HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n")
    assert_receive {:request_started, handler}, 1_000

    shutdown = Task.async(fn -> Supervisor.stop(supervisor) end)

    wait_until(fn -> :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 100) end, fn
      {:error, :econnrefused} ->
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

  test "restarts the endpoint and queues when Oban restarts" do
    Process.exit(Oban.whereis(@oban_name), :kill)

    assert_receive {:endpoint_starting, nil}, 5_000
    assert_receive {:performed, "http://localhost"}, 5_000
    assert %{paused: false} = Oban.check_queue(@oban_name, queue: :shutdown_test)
  end

  test "a queue restart doesn't leave it paused" do
    producer = Oban.Registry.whereis(@oban_name, {:producer, "shutdown_test"})
    Process.exit(producer, :kill)

    wait_until(fn -> Oban.Registry.whereis(@oban_name, {:producer, "shutdown_test"}) end, fn pid ->
      is_pid(pid) and pid != producer
    end)

    assert {:ok, _job} = Oban.insert(@oban_name, Worker.new(%{test_pid: self() |> :erlang.pid_to_list() |> to_string()}))
    assert_receive {:performed, "http://localhost"}, 5_000
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
