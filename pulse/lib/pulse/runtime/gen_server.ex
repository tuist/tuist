defmodule Pulse.Runtime.GenServer do
  @moduledoc false
  defmacro __using__(opts) do
    quote do: use(Elixir.GenServer, unquote(opts))
  end

  def start_link(module, args, opts \\ []), do: Pulse.Runtime.server_start(module, args, opts)
  def call(server, request, timeout \\ 5000), do: Pulse.Runtime.call(server, request, timeout)
  def cast(server, request), do: Pulse.Runtime.cast(server, request)
  def stop(server, reason \\ :normal, timeout \\ :infinity), do: Pulse.Runtime.stop(server, reason, timeout)
  def whereis(server), do: Pulse.Runtime.whereis(server)
  def reply(from, reply), do: Elixir.GenServer.reply(from, reply)
end
