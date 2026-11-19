defmodule Condukt.Sandbox.SessionProcessesTest do
  # Terminal, services, setup, and the lazy second sandbox, against the
  # local sandbox's processes.
  use ExUnit.Case, async: true

  alias Condukt.Sandbox
  alias Condukt.Sandbox.{Lazy, Services, Setup, Sync, Terminal}
  alias Condukt.Test.OutageSandbox

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    {:ok, sandbox} = Sandbox.new(Sandbox.Local, cwd: tmp_dir, process_dir: Path.join(tmp_dir, "processes"))
    %{sandbox: sandbox}
  end

  test "a terminal runs a shell on a pty that takes input, and stopping it kills the shell", %{sandbox: sandbox} do
    {:ok, term} = Terminal.start_link(sandbox, id: "term", shell: "bash --norc --noprofile -i")
    {:ok, _scrollback} = Terminal.subscribe(term)

    :ok = Terminal.write(term, "tty >/dev/null && echo on-a-tty-$((6 * 7))\r")
    assert await_output("on-a-tty-42")

    Terminal.stop(term)
    assert {:error, :not_found} = Sandbox.read_process(sandbox, "term", 0)
  end

  test "services start, report ready, restart after exiting, and outlive nothing but the services process",
       %{sandbox: sandbox, tmp_dir: tmp_dir} do
    counter = Path.join(tmp_dir, "starts")

    {:ok, services} =
      Services.start_link(sandbox,
        owner: "session",
        subscribers: [self()],
        services: [
          %{name: "flaky", command: "echo x >> #{counter}; sleep 0.2; exit 1", restart: :on_failure},
          %{name: "steady", command: "touch #{tmp_dir}/up; exec sleep 60", ready: {:command, "test -e #{tmp_dir}/up"}}
        ]
      )

    assert_receive {Services, "steady", :ready}, 5_000
    assert_receive {Services, "flaky", :exited}, 5_000

    # Restarted after its one-second backoff.
    assert eventually(fn -> counter |> File.read!() |> String.split() |> length() >= 2 end)
    assert %{name: "steady", status: :ready, url: nil} = Enum.find(Services.list(services), &(&1.name == "steady"))

    id = Services.process_id("session", "steady")
    assert {:ok, %{status: :running}} = Sandbox.read_process(sandbox, id, 0)
    GenServer.stop(services)
    assert {:error, :not_found} = Sandbox.read_process(sandbox, id, 0)
  end

  test "a service the sandbox cannot be read for is left running", %{tmp_dir: tmp_dir} do
    {:ok, sandbox} = Sandbox.new(OutageSandbox, cwd: tmp_dir, process_dir: Path.join(tmp_dir, "processes"))
    starts = Path.join(tmp_dir, "starts")

    {:ok, services} =
      Services.start_link(sandbox,
        owner: "session",
        subscribers: [self()],
        services: [%{name: "web", command: "echo x >> #{starts}; exec sleep 60"}]
      )

    assert_receive {Services, "web", :ready}, 5_000
    File.touch!(Path.join(tmp_dir, "outage"))
    Process.sleep(1_500)
    File.rm!(Path.join(tmp_dir, "outage"))
    Process.sleep(1_500)

    assert [%{name: "web", status: :ready, restarts: 0}] = Services.list(services)
    assert File.read!(starts) == "x\n"
    GenServer.stop(services)
  end

  test "setup streams its output and fails with the output's end", %{sandbox: sandbox} do
    parent = self()
    on_output = &send(parent, {:output, &1})

    # Local saves no snapshots.
    assert {:ok, %{snapshot: nil}} = Setup.prepare(sandbox, "echo installing; echo done", on_output: on_output)
    assert_received {:output, _}

    assert {:error, {:setup_failed, {:exited, 3}, tail}} = Setup.resume(sandbox, "echo broke; exit 3")
    assert tail =~ "broke"
  end

  test "a lazy sandbox starts on first use, mirrors before it, and lets go when idle",
       %{sandbox: linux, tmp_dir: tmp_dir} do
    File.mkdir_p!(Path.join(tmp_dir, "repo"))
    File.write!(Path.join(tmp_dir, "repo/a.txt"), "one")
    mac_dir = Path.join(tmp_dir, "mac")
    File.mkdir_p!(mac_dir)

    {:ok, mac} =
      Sandbox.new(Lazy,
        sandbox: {Sandbox.Local, cwd: mac_dir, process_dir: Path.join(tmp_dir, "mac-processes")},
        idle_after: 100,
        before_use: fn mac -> :ok = Sync.mirror(linux, "repo", mac, "work", clean: true) end
      )

    assert {:ok, "one"} = Sandbox.read(mac, "work/a.txt")
    File.write!(Path.join(tmp_dir, "repo/b.txt"), "two")
    File.rm!(Path.join(tmp_dir, "repo/a.txt"))
    Process.sleep(1_100)

    assert {:ok, %{output: "b.txt\n"}} = Sandbox.exec(mac, "ls work", [])
    assert %Sandbox{module: Sandbox.Local} = Lazy.sandbox(mac)

    # Following a running process, as a parked command's watcher does, does
    # not sync under it.
    assert :ok = Sandbox.start_process(mac, "follow", "sleep 5", [])
    File.write!(Path.join(tmp_dir, "repo/c.txt"), "three")
    Process.sleep(1_100)
    assert {:ok, %{status: :running}} = Sandbox.read_process(mac, "follow", 0)
    refute File.exists?(Path.join(mac_dir, "work/c.txt"))
    assert :ok = Sandbox.stop_process(mac, "follow")
  end

  test "listing services answers while a readiness probe runs", %{sandbox: sandbox} do
    {:ok, services} =
      Services.start_link(sandbox,
        owner: "slow-probe",
        services: [%{name: "web", command: "sleep 30", ready: {:command, "sleep 4"}}]
      )

    # A check round is probing by now.
    Process.sleep(1_500)
    {micros, list} = :timer.tc(fn -> Services.list(services) end)
    assert [%{name: "web", status: :starting}] = list
    assert micros < 1_000_000
    GenServer.stop(services)
  end

  test "setup and the terminal ride out failed reads", %{tmp_dir: tmp_dir} do
    {:ok, sandbox} =
      Sandbox.new(OutageSandbox, cwd: tmp_dir, process_dir: Path.join(tmp_dir, "outage-processes"))

    outage = Path.join(tmp_dir, "outage")
    lift = fn -> Task.start(fn -> Process.sleep(1_500) && File.rm!(outage) end) end

    File.touch!(outage)
    lift.()
    assert {:ok, %{snapshot: nil}} = Setup.prepare(sandbox, "sleep 1; echo done")

    {:ok, term} = Terminal.start_link(sandbox, id: "term", shell: "bash --norc --noprofile -i")
    {:ok, _scrollback} = Terminal.subscribe(term)
    File.touch!(outage)
    lift.()
    :ok = Terminal.write(term, "echo after-$((6 * 7))\r")
    assert await_output("after-42", "", 10_000)
    Terminal.stop(term)
  end

  test "a lazy sandbox's calls wait for a before_use that is running", %{tmp_dir: tmp_dir} do
    {:ok, mac} =
      Sandbox.new(Lazy,
        sandbox: {Sandbox.Local, cwd: tmp_dir},
        before_use: fn mac ->
          Process.sleep(300)
          :ok = Sandbox.write(mac, "synced.txt", "fresh")
        end
      )

    first = Task.async(fn -> Sandbox.read(mac, "synced.txt") end)
    Process.sleep(50)
    second = Task.async(fn -> Sandbox.read(mac, "synced.txt") end)

    assert Task.await(first) == {:ok, "fresh"}
    assert Task.await(second) == {:ok, "fresh"}
  end

  test "a lazy sandbox is let go when the process that created it exits", %{tmp_dir: tmp_dir} do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, mac} = Sandbox.new(Lazy, sandbox: {Sandbox.Local, cwd: tmp_dir})
        {:ok, _output} = Sandbox.exec(mac, "true", [])
        send(parent, {:mac, mac})
        receive do: (:exit -> :ok)
      end)

    assert_receive {:mac, %Sandbox{state: server}}, 5_000
    ref = Process.monitor(server)
    send(owner, :exit)
    assert_receive {:DOWN, ^ref, :process, ^server, :normal}, 5_000

    # Given another owner, it outlives the process that created it.
    keeper = spawn(fn -> receive do: (:exit -> :ok) end)

    creator =
      spawn(fn ->
        {:ok, mac} = Sandbox.new(Lazy, sandbox: {Sandbox.Local, cwd: tmp_dir}, owner: keeper)
        send(parent, {:mac, mac})
      end)

    assert_receive {:mac, %Sandbox{state: kept} = mac}, 5_000
    creator_ref = Process.monitor(creator)
    assert_receive {:DOWN, ^creator_ref, :process, ^creator, _reason}, 5_000
    assert {:ok, %{exit_code: 0}} = Sandbox.exec(mac, "true", [])

    kept_ref = Process.monitor(kept)
    send(keeper, :exit)
    assert_receive {:DOWN, ^kept_ref, :process, ^kept, :normal}, 5_000
  end

  defp await_output(text, buffer \\ "", timeout \\ 5_000) do
    receive do
      {Terminal, "term", {:output, chunk}} ->
        buffer = buffer <> chunk
        if buffer =~ text, do: true, else: await_output(text, buffer, timeout)
    after
      timeout -> flunk("no #{inspect(text)} in #{inspect(buffer)}")
    end
  end

  defp eventually(fun, attempts \\ 200) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(50) && eventually(fun, attempts - 1)
    end
  end
end
