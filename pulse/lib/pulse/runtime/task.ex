defmodule Pulse.Runtime.Task do
  @moduledoc false
  def child_spec(fun), do: Task.child_spec(Pulse.Runtime.capture(fun))
  def start_link(fun), do: Task.start_link(Pulse.Runtime.capture(fun))
  def yield(task, timeout \\ 5000), do: Task.yield(task, timeout)
  def await(task, timeout \\ 5000), do: Task.await(task, timeout)
  def shutdown(task, reason \\ 5000), do: Task.shutdown(task, reason)
  def ignore(task), do: Task.ignore(task)
  def async(fun), do: Task.async(Pulse.Runtime.capture(fun))

  def async_stream(collection, fun, opts) do
    runtime = Pulse.Runtime.current()
    Task.async_stream(collection, fn item -> Pulse.Runtime.with(runtime, fn -> fun.(item) end) end, opts)
  end
end
