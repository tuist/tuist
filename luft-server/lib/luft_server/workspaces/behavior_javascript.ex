defmodule LuftServer.Workspaces.BehaviorJavaScript do
  @moduledoc "Isolated JavaScript with callbacks marshalled onto the transaction owner."

  @runtime __MODULE__.Runtime

  def child_spec do
    if match?({:unix, :linux}, :os.type()) do
      {Javex.Runtime,
       name: @runtime, backend: :isolated, max_concurrency: 2, max_process_memory: 536_870_912}
    end
  end

  def identity do
    provider = @runtime |> Javex.Runtime.plugin_bytes() |> :erlang.iolist_to_binary()

    "luft-1/javex-#{Application.spec(:javex, :vsn)}/" <>
      Base.encode16(:crypto.hash(:sha256, provider), case: :lower)
  end

  def compile(source) do
    script = """
    const buffer = new Uint8Array(65536);
    let n = 0, count;
    while ((count = Javy.IO.readSync(0, buffer.subarray(n))) > 0) n += count;
    const input = JSON.parse(new TextDecoder().decode(buffer.subarray(0,n)));
    const execute = async (input) => { #{source} };
    const result = await execute(input);
    Javy.IO.writeSync(1, new TextEncoder().encode(JSON.stringify(result)));
    """

    Javex.compile(script, runtime: @runtime, timeout: 30_000, max_source: 36_000)
  end

  def execute(compiled, input, callback) do
    owner = self()
    key = make_ref()

    task =
      Task.async(fn ->
        bridge = fn name ->
          fn argument, %{deadline: deadline} ->
            ref = make_ref()
            send(owner, {key, self(), ref, name, argument})

            receive do
              {^ref, result} -> result
            after
              max(0, deadline - System.monotonic_time(:millisecond)) ->
                {:error, %{"code" => "timeout", "message" => "Execution budget exceeded"}}
            end
          end
        end

        Javex.run(compiled, input,
          runtime: @runtime,
          timeout: 5_000,
          fuel: 5_000_000,
          max_memory: 16_777_216,
          max_input: 65_536,
          max_output: 65_536,
          max_stderr: 0,
          max_callback_calls: 8,
          max_callback_concurrency: 1,
          callback_timeout: 2_000,
          max_callback_input: 16_384,
          max_callback_output: 65_536,
          callbacks:
            Map.new(~w(resources.get resources.create resources.update), &{&1, bridge.(&1)})
        )
      end)

    try do
      pump(task, key, callback)
    after
      Task.shutdown(task, :brutal_kill)
    end
  end

  defp pump(task, key, callback) do
    receive do
      {^key, pid, ref, name, argument} ->
        result = callback.(name, argument)
        send(pid, {ref, result})
        pump(task, key, callback)

      {ref, result} when ref == task.ref ->
        Process.demonitor(ref, [:flush])
        result

      {:DOWN, ref, :process, _, _} when ref == task.ref ->
        {:error, :execution_failed}
    after
      6_000 -> {:error, :execution_timeout}
    end
  end
end
