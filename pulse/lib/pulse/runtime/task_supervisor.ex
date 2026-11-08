defmodule Pulse.Runtime.Task.Supervisor do
  @moduledoc false
  def child_spec(opts), do: Task.Supervisor.child_spec(opts)

  def start_link(opts \\ []) do
    opts =
      Keyword.update(opts, :name, nil, &Pulse.Runtime.name/1)
      |> Keyword.reject(fn {k, v} -> k == :name and v == nil end)

    Task.Supervisor.start_link(opts)
  end

  def async_nolink(supervisor, fun),
    do: Task.Supervisor.async_nolink(Pulse.Runtime.name(supervisor), Pulse.Runtime.capture(fun))

  def start_child(supervisor, fun),
    do: Task.Supervisor.start_child(Pulse.Runtime.name(supervisor), Pulse.Runtime.capture(fun))

  def children(supervisor), do: Task.Supervisor.children(Pulse.Runtime.name(supervisor))
  def terminate_child(supervisor, pid), do: Task.Supervisor.terminate_child(Pulse.Runtime.name(supervisor), pid)
end
