defmodule Atlas.TestSupport.Agents.NoopRuntime do
  @moduledoc false

  def run(prompt, _context, _opts), do: {:ok, "handled: #{prompt}"}
end
