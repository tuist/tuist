defmodule ScaleEndToEndController do
  def start(host, port) do
    node = String.to_atom("tuist_e2e@#{host}")
    if !Node.connect(node), do: launch(host, port)

    Enum.reduce_while(1..1200, false, fn _, _ ->
      ready =
        Node.connect(node) and
          try do
            :erpc.call(node, Process, :whereis, [TuistWeb.Endpoint]) != nil and
              :erpc.call(node, Process, :whereis, [Tuist.Marketing.Stats]) != nil
          catch
            _, _ -> false
          end

      if ready,
        do: {:halt, true},
        else:
          (
            Process.sleep(50)
            {:cont, false}
          )
    end) || raise "Full server did not start"

    {node, node}
  end

  def launch(host, port) do
    parent = self()

    spawn(fn ->
      executable = Path.expand("../../../bin/elixir", Path.dirname(to_string(:code.which(Kernel))))
      address = "{" <> String.replace(host, ".", ",") <> "}"

      flags =
        "+S 2:2 -erl_epmd_port 19110 -kernel inet_dist_use_interface #{address} inet_dist_listen_min 19110 inet_dist_listen_max 19110"

      args = [
        "--name",
        "tuist_e2e@#{host}",
        "--cookie",
        Atom.to_string(Node.get_cookie()),
        "-S",
        "mix",
        "run",
        "--no-compile",
        "--no-start",
        Path.join(__DIR__, "server.exs")
      ]

      env = [
        {~c"ERL_FLAGS", String.to_charlist(flags)},
        {~c"TUIST_E2E_PORT", Integer.to_charlist(port)},
        {~c"PATH", String.to_charlist(Path.join(to_string(:code.root_dir()), "bin") <> ":" <> System.get_env("PATH"))}
      ]

      child = Port.open({:spawn_executable, executable}, [:binary, :exit_status, :stderr_to_stdout, args: args, env: env])
      send(parent, :launched)
      loop(child, "/tmp/tuist-scale-e2e/server-#{port}.log")
    end)

    receive do
      :launched -> :ok
    after
      5000 -> raise "Could not launch full server"
    end
  end

  def loop(port, path) do
    receive do
      {^port, {:data, data}} ->
        File.write!(path, data, [:append])
        loop(port, path)

      {^port, {:exit_status, _}} ->
        :ok
    end
  end

  def stop(node) do
    pid = :erpc.call(node, System, :pid, [])
    {_, 0} = System.cmd("kill", ["-TERM", pid])

    Enum.reduce_while(1..1200, false, fn _, _ ->
      if Node.ping(node) == :pang,
        do: {:halt, true},
        else:
          (
            Process.sleep(50)
            {:cont, false}
          )
    end) || raise "Full server did not stop"

    :ok
  end
end
