defmodule Condukt.Agent do
  @moduledoc """
  Macro for defining Condukt agents with explicit agent options.

  `use Condukt.Agent` is equivalent to `use Condukt`. Passing `:runtime`
  selects the component that owns the agent loop:

      defmodule MyApp.Implementer do
        use Condukt.Agent, runtime: MyApp.CodexRuntime
      end

  The native runtime remains the default.
  """

  defmacro __using__(opts) do
    quote location: :keep do
      use Condukt, unquote(opts)
    end
  end
end
