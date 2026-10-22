defmodule Atlas.Automations.JavaScript do
  @moduledoc "Bounded, computation-only JavaScript. Unsupported isolation fails closed."

  alias Atlas.Automations.Contract
  alias Atlas.Automations.JavaScript.Runtime

  @runtime Runtime

  def child_spec do
    if supported?() do
      {Javex.Runtime, name: @runtime, backend: :isolated, max_concurrency: 2, max_process_memory: 512 * 1024 * 1024}
    end
  end

  def supported?, do: match?({:unix, :linux}, :os.type())

  def evaluate(source, input) when is_binary(source) and is_map(input) do
    cond do
      byte_size(source) > 65_536 -> {:error, "JavaScript source exceeds 64 KiB."}
      not Contract.within_budget?(input, 65_536) -> {:error, "JavaScript input exceeds its size or nesting budget."}
      not supported?() -> {:error, "Untrusted JavaScript requires the Linux isolated executor."}
      true -> execute(source, input)
    end
  end

  defp execute(source, input) do
    script = """
    const chunks = [];
    const buffer = new Uint8Array(4096);
    let count;
    while ((count = Javy.IO.readSync(0, buffer)) > 0) chunks.push(buffer.slice(0, count));
    const bytes = new Uint8Array(chunks.reduce((n, chunk) => n + chunk.length, 0));
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    const input = JSON.parse(new TextDecoder().decode(bytes));
    const evaluate = (input) => {
      #{source}
    };
    const output = evaluate(input);
    if (output === null || typeof output !== 'object' || Array.isArray(output)) {
      throw new Error('An object result is required');
    }
    Javy.IO.writeSync(1, new TextEncoder().encode(JSON.stringify(output)));
    """

    with {:ok, compiled} <- Javex.compile(script, runtime: @runtime, timeout: 5000, max_source: 70_000),
         {:ok, output} <-
           Javex.run(compiled, input,
             runtime: @runtime,
             timeout: 1000,
             fuel: 5_000_000,
             max_memory: 16 * 1024 * 1024,
             max_input: 65_536,
             max_output: 65_536,
             max_stderr: 1024
           ) do
      {:ok, output}
    else
      {:error, _} -> {:error, "JavaScript evaluation failed or exceeded its execution budget."}
    end
  end
end
