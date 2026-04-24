defmodule Processor.InFlight do
  @moduledoc """
  Tracks the number of builds the node is currently processing.

  Read by the `GET /stats` endpoint so the dispatching server can pick the
  least-busy replica across a ReplicaSet. Backed by `:atomics` for lock-free
  reads and writes.
  """

  @name __MODULE__

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> :atomics.new(1, signed: true) end, name: @name)
  end

  def child_spec(_opts) do
    %{id: @name, start: {__MODULE__, :start_link, [[]]}, type: :worker}
  end

  def track(fun) when is_function(fun, 0) do
    incr()

    try do
      fun.()
    after
      decr()
    end
  end

  def count do
    :atomics.get(ref(), 1)
  end

  defp incr, do: :atomics.add(ref(), 1, 1)
  defp decr, do: :atomics.sub(ref(), 1, 1)

  defp ref, do: Agent.get(@name, & &1)
end
